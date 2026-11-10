# Reproducible environment for the stockcast experiments.
# CRAN is pinned to a dated Posit Package Manager snapshot so that package
# versions are frozen; R itself is pinned by the base image tag.
FROM rocker/r-ver:4.6.2

# The binary repo must match the base image's Ubuntu release (rocker moved
# from noble to resolute in 4.6.2); binaries built for another release fail to
# load their system libraries.
ARG CRAN_DATE=2026-09-01
RUN . /etc/os-release \
    && echo "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/${VERSION_CODENAME}/${CRAN_DATE}'))" \
       >> /usr/local/lib/R/etc/Rprofile.site

RUN apt-get update && apt-get install -y --no-install-recommends \
      make git pandoc libcurl4-openssl-dev libssl-dev libxml2-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
      libpng-dev libtiff5-dev libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY DESCRIPTION .
RUN R -q -e 'install.packages(c("pak", "roxygen2")); pak::local_install_deps(dependencies = TRUE)'

COPY . .
RUN R -q -e 'roxygen2::roxygenise()' && R CMD INSTALL --no-multiarch --no-docs .

CMD ["make", "test"]
