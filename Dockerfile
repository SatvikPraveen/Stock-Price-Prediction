# Reproducible environment for the stockcast experiments.
# CRAN is pinned to a dated Posit Package Manager snapshot so that package
# versions are frozen; R itself is pinned by the base image tag.
FROM rocker/r-ver:4.5.2

ARG CRAN_DATE=2026-09-01
ENV CRAN="https://packagemanager.posit.co/cran/__linux__/noble/${CRAN_DATE}"
RUN echo "options(repos = c(CRAN = '${CRAN}'))" >> /usr/local/lib/R/etc/Rprofile.site

RUN apt-get update && apt-get install -y --no-install-recommends \
      make git pandoc libcurl4-openssl-dev libssl-dev libxml2-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
      libpng-dev libtiff5-dev libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY DESCRIPTION .
RUN R -q -e 'install.packages("pak"); pak::local_install_deps(dependencies = TRUE)'

COPY . .
RUN R -q -e 'roxygen2::roxygenise()' && R CMD INSTALL --no-multiarch --no-docs .

CMD ["make", "test"]
