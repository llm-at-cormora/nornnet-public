# Layer 3: Application layer
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Copy application files
COPY app/ /opt/nornnet/app/

# Application entry point
CMD ["/opt/nornnet/app/entrypoint.sh"]

# Labels for this layer
LABEL org.opencontainers.image.title="Nornnet Application"
LABEL org.opencontainers.image.version="0.1.0"
