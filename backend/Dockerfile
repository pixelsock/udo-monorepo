# Dockerfile for Directus deployment on Render
FROM directus/directus:latest

# Copy all extensions that are tracked in git (with their pre-built dist folders)
# Note: collaborative-editing is not in git, so it's excluded from Docker build
COPY --chown=node:node ./extensions/input-rich-text-html /directus/extensions/input-rich-text-html
COPY --chown=node:node ./extensions/ai-proxy-endpoint /directus/extensions/ai-proxy-endpoint
COPY --chown=node:node ./extensions/migration-bundle /directus/extensions/migration-bundle
COPY --chown=node:node ./extensions/orama-search-bundle /directus/extensions/orama-search-bundle
COPY --chown=node:node ./extensions/pdf-viewer-interface /directus/extensions/pdf-viewer-interface
COPY --chown=node:node ./extensions/udo-theme /directus/extensions/udo-theme

# Set proper permissions
USER root
RUN chown -R node:node /directus/extensions && \
    chmod -R 755 /directus/extensions
USER node

# (Optional) Copy uploads if you want to pre-populate files
# COPY ./uploads /directus/uploads

WORKDIR /directus

EXPOSE 8055

# Default CMD is inherited from the base image