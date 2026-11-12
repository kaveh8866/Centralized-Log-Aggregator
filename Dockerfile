# Centralized Log Aggregator — Fluent Bit collector image.
#
# The pipeline configs are baked into the image on purpose: the collector that
# runs on OCI, AWS, GCP or a laptop is byte-identical, so log parsing and labels
# cannot drift between environments. Rebuild after editing configs/fluent-bit/.
#
# Build (from the repository root):
#   docker build -t cloudguard/fluent-bit-pipeline:local .
#
# Multi-arch: the base image publishes amd64 and arm64 variants, which covers
# OCI Always Free ARM (A1) shapes as well as x86 clouds.

FROM fluent/fluent-bit:3.1.9

LABEL org.opencontainers.image.title="cloudguard-fluent-bit-pipeline" \
      org.opencontainers.image.description="Fluent Bit collector shipping Docker container logs to Grafana Loki" \
      org.opencontainers.image.vendor="CloudGuard" \
      org.opencontainers.image.licenses="Apache-2.0"

COPY configs/fluent-bit/fluent-bit.conf /fluent-bit/etc/fluent-bit.conf
COPY configs/fluent-bit/parsers.conf /fluent-bit/etc/parsers.conf

# Metrics/health endpoint used by the compose port mapping (loopback only).
EXPOSE 2020

ENTRYPOINT ["/fluent-bit/bin/fluent-bit"]
CMD ["--config", "/fluent-bit/etc/fluent-bit.conf"]
