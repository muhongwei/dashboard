#!/usr/bin/env bash
# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Exit on error.
set -e

# Import config.
ROOT_DIR="$(cd $(dirname "${BASH_SOURCE}")/../.. && pwd -P)"
. "${ROOT_DIR}/aio/scripts/conf.sh"

# Declare variables.
CROSS=false
FRONTEND_ONLY=false

function clean {
  rm -rf ${DIST_DIR} ${TMP_DIR}
}

function build::frontend {
  # It is placed only here because all Docker-related scripts use it.
  say "\nReplacing variables in ${ENV_PROD_FILE} file"
  [[ -n ${TRAVIS_COMMIT} ]] && ${REPLACE_BIN} '%GIT_COMMIT%' ${TRAVIS_COMMIT} ${ENV_PROD_FILE}
  [[ -n ${APP_VERSION} ]] && ${REPLACE_BIN} '%VERSION%' ${APP_VERSION} ${ENV_PROD_FILE}

  say "\nBuilding frontend for default locale: en"
  mkdir -p ${FRONTEND_DIR}/en
  ${NG_BIN} build --aot --prod --outputPath=${TMP_DIR}/frontend/en

  languages=($(ls i18n | awk -F"." '{if (NF>2) print $2}'))
  for language in "${languages[@]}"; do
    mkdir -p ${FRONTEND_DIR}/${language}

    say "Building frontend for locale: ${language}"
    ${NG_BIN} build --aot \
                    --prod \
                    --i18nFile=${I18N_DIR}/messages.${language}.xlf \
                    --i18nFormat=xlf \
                    --locale=${language} --outputPath=${TMP_DIR}/frontend/${language}
  done

  say "\nReverting variables in ${ENV_PROD_FILE} file"
  [[ -n ${TRAVIS_COMMIT} ]] && ${REPLACE_BIN} ${TRAVIS_COMMIT} '%GIT_COMMIT%' ${ENV_PROD_FILE}
  [[ -n ${APP_VERSION} ]] && ${REPLACE_BIN} ${APP_VERSION} '%VERSION%'  ${ENV_PROD_FILE}
}

function build::backend {
  say "\nBuilding backend"
  ${GULP_BIN} backend:prod
}

function build::backend::cross {
  say "\nBuilding backends for all supported architectures"
  ${GULP_BIN} backend:prod:cross
}

function copy::frontend {
  say "\nCopying frontend to backend dist dir"
  languages=($(ls ${FRONTEND_DIR}))
  architectures=($(ls ${DIST_DIR}))
  for arch in "${architectures[@]}"; do
    for language in "${languages[@]}"; do
      OUT_DIR=${DIST_DIR}/${arch}/public
      mkdir -p ${OUT_DIR}
      cp -r ${FRONTEND_DIR}/${language} ${OUT_DIR}
    done
  done
}

function copy::supported-locales {
  say "\nCopying locales file to backend dist dirs"
  architectures=($(ls ${DIST_DIR}))
  for arch in "${architectures[@]}"; do
    OUT_DIR=${DIST_DIR}/${arch}
    cp ${I18N_DIR}/locale_conf.json ${OUT_DIR}
  done
}

function copy::dockerfile {
  say "\nCopying Dockerfile to backend dist dirs"
  architectures=($(ls ${DIST_DIR}))
  for arch in "${architectures[@]}"; do
    OUT_DIR=${DIST_DIR}/${arch}
    cp ${AIO_DIR}/Dockerfile ${OUT_DIR}
  done
}

function parse::args {
  POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    key="$1"
    case ${key} in
      -c|--cross)
      CROSS=true
      shift
      ;;
      --frontend-only)
      FRONTEND_ONLY=true
      shift
      ;;
    esac
  done
  set -- "${POSITIONAL[@]}" # Restore positional parameters.
}

# Execute script.
START=$(date +%s.%N)

parse::args "$@"
clean

if [ "${FRONTEND_ONLY}" = true ] ; then
  build::frontend
  exit
fi

if [ "${CROSS}" = true ] ; then
  build::backend::cross
else
  build::backend
fi

build::frontend
copy::frontend
copy::supported-locales
copy::dockerfile

END=$(date +%s.%N)
TOOK=$(echo "$END - $START" | bc)
say "\nBuild finished successfully after ${TOOK}s"
