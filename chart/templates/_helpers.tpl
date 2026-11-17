{{/*
Gets elasticsearch password either from a defined secret or grabs the one specified
in values.yaml file directly.
*/}}
{{- define "malcolm.elasticsearchpassword" -}}
    {{- if .Values.external_elasticsearch.password }}
        {{- printf "%s" .Values.external_elasticsearch.password }}
    {{- else if .Values.external_elasticsearch.elastic_secret_name }}
        {{- $elastic_secret := (lookup "v1" "Secret" .Values.external_elasticsearch.namespace .Values.external_elasticsearch.elastic_secret_name).data }}
        {{- $elastic_password := get $elastic_secret "password" | b64dec }}
        {{- printf "%s" $elastic_password }}
    {{- else }}
        {{- printf "%s" "" }}
    {{- end }}
{{- end }}


{{/*
Get whether or not opensearch is local or remote.
*/}}
{{- define "malcolm.opensearchprimary" -}}
    {{- if .Values.opensearch.enabled }}
        {{- printf "%s" "opensearch-local" }}
    {{- else if .Values.external_elasticsearch.enabled }}
        {{- printf "%s" "elasticsearch-remote" }}
    {{- else }}
        {{- printf "%s" "opensearch-local" }}
    {{- end }}
{{- end }}

{{/*
Get Opensearch or Elasticsearch url.
*/}}
{{- define "malcolm.opensearchprimaryurl" -}}
{{- if .Values.opensearch.enabled }}
    {{- printf "%s" .Values.opensearch.url }}
{{- else if .Values.external_elasticsearch.enabled }}
    {{- $url := .Values.external_elasticsearch.url }}
    {{- if .Values.external_elasticsearch.username }}
        {{- $parts := split "://" .Values.external_elasticsearch.url }}
        {{- $url := printf "%s://%s" $parts._0 .Values.external_elasticsearch.username }}
        {{- $elastic_password := include "malcolm.elasticsearchpassword" . -}}
        {{- if $elastic_password }}
            {{- $url = printf "%s:%s" $url $elastic_password }}
        {{- end }}
        {{- $url = printf "%s@%s" $url $parts._1 }}
        {{- printf "%s" $url }}
    {{- else }}
        {{- printf "%s" $url }}
    {{- end }}
{{- else }}
    {{- printf "%s" .Values.opensearch.url }}
{{- end }}
{{- end }}


{{/*
Get Opensearch or Elasticsearch dashboards url. TODO figure out a way to refactor this so
I am not duplicating this template code.
*/}}
{{- define "malcolm.dashboardsurl" -}}
{{- if .Values.opensearch.enabled }}
    {{- printf "%s" .Values.opensearch.dashboards_url }}
{{- else if .Values.external_elasticsearch.enabled }}
    {{- $url := .Values.external_elasticsearch.dashboards_url }}
    {{- if .Values.external_elasticsearch.username }}
        {{- $parts := split "://" .Values.external_elasticsearch.dashboards_url }}
        {{- $url := printf "%s://%s" $parts._0 .Values.external_elasticsearch.username }}
        {{- $elastic_password := include "malcolm.elasticsearchpassword" . -}}
        {{- if $elastic_password }}
            {{- $url = printf "%s:%s" $url $elastic_password }}
        {{- end }}
        {{- $url = printf "%s@%s" $url $parts._1 }}
        {{- printf "%s" $url }}
    {{- else }}
        {{- printf "%s" $url }}
    {{- end }}
{{- else }}
    {{- printf "%s" .Values.opensearch.dashboards_url }}
{{- end }}
{{- end }}


{{/*
Used for secret generation for the opensearch-curlrc Kubernetes secret
*/}}
{{- define "malcolm.curlrc" -}}
{{- if .Values.external_elasticsearch.username }}
    {{- $elastic_password := include "malcolm.elasticsearchpassword" . -}}
    {{- if $elastic_password }}
        {{- printf "--user %s:%s \n--insecure " .Values.external_elasticsearch.username $elastic_password | b64enc | quote }}
    {{- else }}
        {{- printf "--user %s \n--insecure " .Values.external_elasticsearch.username | b64enc | quote }}
    {{- end }}
{{- else }}
    {{- "" | b64enc | quote }}
{{- end }}
{{- end }}


{{/*
Parse a JVM heap size (in whole MiB) out of a -Xmx/-Xms style options string,
e.g. "-Xmx32g -Xms32g -Xss256k" yields 32768. Returns 0 if neither is present.
Mirrors GetMemMegabytesFromJavaOptsLine in Malcolm's scripts/malcolm_common.py,
which the vanilla-manifest deployment path uses for the same purpose.
*/}}
{{- define "malcolm.javaHeapMib" -}}
{{- $opts := . | default "" -}}
{{- $mib := 0 -}}
{{- range $opt := (list "Xmx" "Xms") -}}
  {{- if eq $mib 0 -}}
    {{- range $match := (regexFindAll (printf "-%s[0-9]+[kKmMgG]" $opt) $opts 1) -}}
      {{- $n := regexFind "[0-9]+" $match | atoi -}}
      {{- $unit := regexFind "[kKmMgG]$" $match | lower -}}
      {{- if eq $unit "g" -}}
        {{- $mib = mul $n 1024 -}}
      {{- else if eq $unit "m" -}}
        {{- $mib = $n -}}
      {{- else if eq $unit "k" -}}
        {{- $mib = divf $n 1024 | ceil | int -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $mib -}}
{{- end }}


{{/*
Convert a Kubernetes memory quantity (e.g. "512Mi", "2Gi", "1G", "1024") to
whole MiB, for comparison against a JVM heap size. Returns 0 if unparseable.
Mirrors ParseK8sMemoryToMib in Malcolm's scripts/malcolm_common.py.
*/}}
{{- define "malcolm.memoryMib" -}}
{{- $val := . | toString | trim -}}
{{- $digits := regexFind "^[0-9]+" $val | default "" -}}
{{- $mib := 0 -}}
{{- if $digits -}}
  {{- $n := atoi $digits -}}
  {{- $suffix := substr (len $digits | int) (len $val | int) $val -}}
  {{- if eq $suffix "Gi" -}}
    {{- $mib = mul $n 1024 -}}
  {{- else if eq $suffix "Mi" -}}
    {{- $mib = $n -}}
  {{- else if eq $suffix "Ki" -}}
    {{- $mib = divf $n 1024 | floor | int -}}
  {{- else if eq $suffix "G" -}}
    {{- $mib = divf (mul $n 1000000000) 1048576 | floor | int -}}
  {{- else if eq $suffix "M" -}}
    {{- $mib = divf (mul $n 1000000) 1048576 | floor | int -}}
  {{- else -}}
    {{- $mib = divf $n 1048576 | floor | int -}}
  {{- end -}}
{{- end -}}
{{- $mib -}}
{{- end }}


{{/*
Render a container's "resources:" block.

Each component's resources live alongside its other tunables in values.yaml,
under the same development:/production: blocks as settings like java_memory, e.g.
logstash.production.resources. Pass the owning section name as "section":

  {{ include "malcolm.resources" (dict "root" $ "section" "logstash") }}

Resolution order:
  1. an explicit "resources" dict passed by the caller
  2. .Values.<section>.<development|production>.resources, selected by is_production
  3. nothing at all

Nothing is emitted when the result is empty, so that containers without a
configured size do not get a null "resources:" key (a null key is dropped by
kubectl apply but re-rendered by ArgoCD on every refresh, leaving the
Application permanently OutOfSync -- the drift class addressed in #116).

Where the same section configures more than one container (e.g. valkey_env covers
both valkey and valkey-cache), "subkey" selects a nested entry:

  {{ include "malcolm.resources" (dict "root" $ "section" "valkey_env" "subkey" "cache") }}

If the tier block also carries a java_memory setting, the memory request is
floored at that JVM heap size, since -Xms pre-allocates the heap and a request
below it would guarantee the pod exceeds its own request. Malcolm's
scripts/malcolm_kubernetes.py applies the same floor when injecting resources
into the vanilla Kubernetes manifests.
*/}}
{{- define "malcolm.resources" -}}
{{- $root := .root -}}
{{- $tier := ternary "production" "development" $root.Values.is_production -}}
{{- $tierBlock := (get ((get $root.Values (.section | default "")) | default dict) $tier) | default dict -}}
{{- $resources := get $tierBlock "resources" | default dict -}}
{{- if .subkey -}}
  {{- $resources = get $resources .subkey | default dict -}}
{{- end -}}
{{- $resources = .resources | default $resources -}}
{{- $heapMib := include "malcolm.javaHeapMib" (get $tierBlock "java_memory" | default "") | int -}}
{{- if and (gt $heapMib 0) $resources -}}
  {{- $requests := get $resources "requests" | default dict -}}
  {{- if gt $heapMib (include "malcolm.memoryMib" (get $requests "memory" | default "0") | int) -}}
    {{- $resources = set (deepCopy $resources) "requests" (set (deepCopy $requests) "memory" (printf "%dMi" $heapMib)) -}}
  {{- end -}}
{{- end -}}
{{- if $resources -}}
resources:
{{ toYaml $resources | indent 2 }}
{{- end -}}
{{- end }}


{{- define "malcolm.nodeCount" -}}
{{- $labelKey := .Values.node_count_label.key | default "" }}
{{- $labelValue := .Values.node_count_label.value | default "" }}
{{- $nodeCount := 0 }}

{{- range $index, $obj := (lookup "v1" "Node" "" "").items }}
  {{- if index $obj.metadata.labels $labelKey | default "" | eq $labelValue }}
    {{- $nodeCount = add $nodeCount 1 }}
  {{- end }}
{{- end }}

{{- $nodeCount }}
{{- end }}


{{/*
Used to generate discovery seed hosts for opensearch
*/}}
{{- define "malcolm.discoverySeeds" }}
{{- $replicas := int (.Values.opensearch.replicas) }}
{{- range $index, $value := until $replicas -}}
opensearch-{{ $index }}.opensearch-headless.{{ $.Release.Namespace }}.svc.cluster.local:9300,
{{- end -}}
{{- end }}

{{/*
Used to generate manager nodes for opensearch
*/}}
{{- define "malcolm.managerNodes" }}
{{- $replicas := int (.Values.opensearch.replicas) }}
{{- range $index, $value := until $replicas -}}
opensearch-{{ $index }},
{{- end -}}
{{- end }}

{{/*
Generate extra secrets for database
*/}}
{{- define "netbox.databaseExtravars" }}
{{- range $index, $value := .Values.postgres.extra_secrets }}
apiVersion: v1
kind: Secret
type: Opaque
  {{- range $key, $value1 := $value }}
metadata:
  name: {{ $key }}
data:
    {{- range $key1, $value2 := $value1 }}
        {{- if $value2 }}
  {{ $key1 }}: {{ $value2 | b64enc }}
        {{- else }}
  {{ $key1 }}: {{ $.Values.postgres.password | b64enc }}
        {{- end }}
    {{- end }}
  {{- end }}
---
{{- end }}
{{- end }}

{{- define "malcolm.beatstemplate" }}
{
  "index_patterns" : ["{{ .index_patterns }}"],
  "composed_of": [
    "ecs_base",
    "ecs_ecs",
    "ecs_event",
    "ecs_agent",
    "ecs_client",
    "ecs_destination",
    "ecs_error",
    "ecs_file",
    "ecs_host",
    "ecs_http",
    "ecs_log",
    "ecs_network",
    "ecs_process",
    "ecs_related",
    "ecs_server",
    "ecs_source",
    "ecs_threat",
    "ecs_url",
    "ecs_user",
    "ecs_user_agent",
    "custom_miscbeat",
    "custom_suricata_stats",
    "custom_winlog",
    "custom_zeek_diagnostic"
  ],
  "template" :{
    "settings" : {
      "index" : {
        "lifecycle.name": "{{ .ilm_policy }}",
        "lifecycle.rollover_alias": "{{ .rollover_alias }}",
        "mapping.total_fields.limit" : "6000",
        "mapping.nested_fields.limit" : "250",
        "max_docvalue_fields_search" : "200",
        "default_pipeline": "{{ .default_pipeline }}"
      }
    },
    "mappings": {
      "properties": {
        "timestamp": { "type": "date" },
        "node": { "type": "keyword" },
        "event.result": { "type": "keyword" },
        "os.family": { "type": "keyword" },
        "os.type": { "type": "keyword" }
      }
    }
  }
}
{{- end }}

{{- define "malcolm.ecstemplate" }}
{
    "index_patterns" : ["{{ .index_patterns }}"],
    "composed_of": [
        "ecs_base",
        "ecs_ecs",
        "ecs_event",
        "ecs_agent",
        "ecs_client",
        "ecs_destination",
        "ecs_error",
        "ecs_file",
        "ecs_host",
        "ecs_http",
        "ecs_log",
        "ecs_network",
        "ecs_process",
        "ecs_related",
        "ecs_rule",
        "ecs_server",
        "ecs_source",
        "ecs_threat",
        "ecs_url",
        "ecs_vulnerability",
        "ecs_user_agent",
        "custom_arkime",
        "custom_suricata",
        "custom_zeek",
        "custom_zeek_ot",
        "custom_malcolm_common"
    ],
    "template" :{
        "aliases": {
            "{{ .search_alias }}": {}
        },
        "settings" : {
            "index": {
                "lifecycle.name": "{{ .ilm_policy }}",
                "lifecycle.rollover_alias": "{{ .rollover_alias }}",
                "mapping.total_fields.limit": "6000",
                "mapping.nested_fields.limit": "250",
                "max_docvalue_fields_search": "200",
                "number_of_shards": "{{ .number_of_shards }}",
                "number_of_replicas": "{{ .number_of_replicas }}"
            }
        }
  }
}
{{- end }}