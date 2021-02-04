#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

function crd_to_json_schema() {
  local api_version crd_group crd_kind crd_version document input kind

  echo "Processing ${1}..."
  input="input/${1}.yaml"
  curl --silent --show-error "${@:2}" > "${input}"

  for document in $(seq 0 $(($(yq read --collect --doc '*' --length "${input}") - 1))); do
    api_version=$(yq read --doc "${document}" "${input}" apiVersion | cut --delimiter=/ --fields=2)
    kind=$(yq read --doc "${document}" "${input}" kind)
    crd_kind=$(yq read --doc "${document}" "${input}" spec.names.kind | tr '[:upper:]' '[:lower:]')
    crd_group=$(yq read --doc "${document}" "${input}" spec.group | cut --delimiter=. --fields=1)

    if [[ "${kind}" != CustomResourceDefinition ]]; then
      continue
    fi

    case "${api_version}" in
      v1beta1)
        crd_version=$(yq read --doc "${document}" "${input}" spec.version)
        yq read --doc "${document}" --prettyPrint --tojson "${input}" spec.validation.openAPIV3Schema | write_schema "${crd_kind}-${crd_group}-${crd_version}.json"
        ;;

      v1)
        for crd_version in $(yq read --doc "${document}" "${input}" spec.versions.*.name); do
          yq read --doc "${document}" --prettyPrint --tojson "${input}" "spec.versions.(name==${crd_version}).schema.openAPIV3Schema" | write_schema "${crd_kind}-${crd_group}-${crd_version}.json"
        done
        ;;

      *)
        echo "Unknown API version: ${api_version}" >&2
        return 1
        ;;
    esac
  done
}

function write_schema() {
  tee "master-standalone/${1}"
  jq 'def strictify: . + if .type == "object" and has("properties") then {additionalProperties: false} + {properties: (({} + .properties) | map_values(strictify))} else null end; . * {properties: {spec: .properties.spec | strictify}}' "master-standalone/${1}" | tee "master-standalone-strict/${1}"
}

crd_to_json_schema source-controller https://raw.githubusercontent.com/fluxcd/source-controller/main/config/crd/bases/source.toolkit.fluxcd.io_gitrepositories.yaml
crd_to_json_schema helm-controller https://raw.githubusercontent.com/fluxcd/helm-controller/main/config/crd/bases/helm.toolkit.fluxcd.io_helmreleases.yaml
crd_to_json_schema kustomize-controller https://raw.githubusercontent.com/fluxcd/kustomize-controller/main/config/crd/bases/kustomize.toolkit.fluxcd.io_kustomizations.yaml
crd_to_json_schema image-reflector-controller_image-policies https://raw.githubusercontent.com/fluxcd/image-reflector-controller/main/config/crd/bases/image.toolkit.fluxcd.io_imagepolicies.yaml
crd_to_json_schema image-reflector-controller_image-repositories https://raw.githubusercontent.com/fluxcd/image-reflector-controller/main/config/crd/bases/image.toolkit.fluxcd.io_imagerepositories.yaml
crd_to_json_schema notifications-controller_alerts https://raw.githubusercontent.com/fluxcd/notification-controller/main/config/crd/bases/notification.toolkit.fluxcd.io_alerts.yaml
crd_to_json_schema notifications-controller_providers https://raw.githubusercontent.com/fluxcd/notification-controller/main/config/crd/bases/notification.toolkit.fluxcd.io_providers.yaml
crd_to_json_schema notifications-controller_receivers https://raw.githubusercontent.com/fluxcd/notification-controller/main/config/crd/bases/notification.toolkit.fluxcd.io_receivers.yaml
crd_to_json_schema image-automation-controller https://raw.githubusercontent.com/fluxcd/image-automation-controller/main/config/crd/bases/image.toolkit.fluxcd.io_imageupdateautomations.yaml
crd_to_json_schema helm-operator https://raw.githubusercontent.com/fluxcd/helm-operator/master/deploy/crds.yaml
crd_to_json_schema prometheus-operator https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/master/example/prometheus-operator-crd/monitoring.coreos.com_{alertmanagers,podmonitors,probes,prometheuses,prometheusrules,servicemonitors,thanosrulers}.yaml

