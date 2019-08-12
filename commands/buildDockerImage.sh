#!/bin/bash

# Copyright (c) 2019, NVIDIA CORPORATION.

set -e

# Assume this script is in a subdir of the dir containing rapidsdevtool.sh
THISDIR=$(cd $(dirname $0); pwd)
RAPIDSDEVTOOL_DIR=${THISDIR}/..

source ${THISDIR}/utils/common.sh

TIMESTAMP=$(date "+%Y%m%d%H%M%S")
OUTPUT_DIR=${RAPIDSDEVTOOL_DIR}/build-${TIMESTAMP}
RAPIDS_SOURCES_DIR=${OUTPUT_DIR}/rapids
LOG_DIR=${OUTPUT_DIR}/logs
DEBUGFLAG=""
TEMPL_NAME=""
IMAGE_TAG_NAME=""
DOCKERBUILD_ARGS=""
GEND_CLONESCRIPT=${RAPIDS_SOURCES_DIR}/clone.sh
GEND_BUILDSCRIPT=${RAPIDS_SOURCES_DIR}/build.sh
GENDOCKERFILE_CMD=${THISDIR}/genDockerfile.sh
GENCLONESCRIPT_CMD=${THISDIR}/genCloneScript.sh
GENBUILDSCRIPT_CMD=${THISDIR}/genBuildScript.sh
BUILDDOCKERIMAGEFROMFILE_CMD=${THISDIR}/buildDockerImageFromFile.sh

SHORTHELP="$0 [-h|-H] [-d] -t <templateName> [-a <dockerBuildArgs>]"
LONGHELP="${SHORTHELP}
   This command automates the following:
      (setting up a unique build dir to be used as the build context)
      (copying the 'supportfiles' dir)
      (copying the developer 'utils' dir)
      ${GENDOCKERFILE_CMD}
      ${GENBUILDSCRIPT_CMD}
      ${GENCLONESCRIPT_CMD}
      ${BUILDDOCKERIMAGEFROMFILE_CMD}

   The scripts are generated based on the repoSettings file, and the Dockerfile
   is generated based on <templateName> and the dockerArgs file.

   The generated scripts are included in the Docker image where they
   are called as part of the 'docker build' step. Including them in
   the image allows for users to update and/or call them again later
   from inside a container.  See the generated Dockerfile for details
   on how the scripts will be called.

   The image name is generated using the format shown below:

   rapids_<username>-cuda9.2-devel-ubuntu16.04-gcc5-py3.6
                        ^      ^       ^         ^    ^
                        |      type    |         |    python version
                        |              |         |
                        cuda version   |         gcc version
                                       |
                                       linux version

   -a <dockerBuildArgs> can be provided to pass docker args as-is to the build
   command.
"

while getopts ":hHdt:a:" option; do
    case "${option}" in
        h)
            echo "${SHORTHELP}"
            exit 0
            ;;
        H)
            echo "${LONGHELP}"
            exit 0
            ;;
        d)
            DEBUGFLAG=-d
            ;;
	t)
            TEMPL_NAME=${OPTARG}
	    ;;
	a)
            DOCKERBUILD_ARGS=${OPTARG}
	    ;;
	*)
	    echo "${SHORTHELP}"
	    exit 1
    esac
done

if (( $# == 0 )); then
    echo "${SHORTHELP}"
    exit 0
fi

# Enforce all required conditions
ERROR=0
if [[ ${TEMPL_NAME} == "" ]]; then
    echo "${SHORTHELP}"
    echo "ERROR: <templateName> must be specified."
    ERROR=1
fi
if (( ${ERROR} != 0 )); then
    exit ${ERROR}
fi

TEMPL_FILE_NAME=${DOCKER_TEMPL_DIR}/${DOCKERFILE_BASENAME}_${TEMPL_NAME}.template
if [ ! -r ${TEMPL_FILE_NAME} ]; then
    echo "ERROR: ${TEMPL_FILE_NAME} is not a readable file."
    exit 1
fi
# Create the dir to clone into and the build working directory
# Generated files will go in these dirs so they must be created upfront
# TODO: make this configurable
# TODO: should this complain if it already exists?
mkdir -p ${RAPIDS_SOURCES_DIR}

# Copy other dirs that many Dockerfiles expect to copy from their CWD
# FIXME: ensure the copy succeeds
# FIXME: copy the .condarc files directly to the OUTPUT_DIR since
# certain Dockerfiles require this.
cp -a ${RAPIDSDEVTOOL_DIR}/supportfiles ${OUTPUT_DIR}
cp -a ${RAPIDSDEVTOOL_DIR}/supportfiles/.condarc* ${OUTPUT_DIR}
cp -a ${RAPIDSDEVTOOL_DIR}/utils ${OUTPUT_DIR}

# Generate the Dockerfiles
GEND_DOCKERFILE=${OUTPUT_DIR}/${DOCKERFILE_BASENAME}.${TEMPL_NAME}
${GENDOCKERFILE_CMD} ${DEBUGFLAG} -t ${TEMPL_NAME} -o ${GEND_DOCKERFILE}

# Compute the image tag name
# This must be done post-gen since it uses the generated Dockerfile
# TODO: provide an error message if these greps fail
cudaVersion=$(grep "^ARG CUDA_VERSION=" ${GEND_DOCKERFILE} | cut -d'=' -f2)
templType=$(echo ${TEMPL_NAME} | cut -d'-' -f2)
linuxVersion=$(grep "^ARG LINUX_VERSION=" ${GEND_DOCKERFILE} | cut -d'=' -f2)
gccVersion=$(grep "^ARG CXX_VERSION=" ${DOCKERARGS_FILE_NAME} | cut -d'=' -f2)
pyVersion=$(grep "^ARG PYTHON_VERSION=" ${DOCKERARGS_FILE_NAME} | cut -d'=' -f2)

IMAGE_TAG_NAME="rapids_${USER}-cuda${cudaVersion}-${templType}-${linuxVersion}-gcc${gccVersion}-py${pyVersion}"

# Add RAPIDS-wide build.sh and clone.sh scripts
# (most repos have their own build.sh, this is for the others)
${GENBUILDSCRIPT_CMD} ${DEBUGFLAG} -o ${GEND_BUILDSCRIPT}
${GENCLONESCRIPT_CMD} ${DEBUGFLAG} -o ${GEND_CLONESCRIPT}
(cd ${OUTPUT_DIR}; ${BUILDDOCKERIMAGEFROMFILE_CMD} -f ${GEND_DOCKERFILE} -l ${LOG_DIR} -i ${IMAGE_TAG_NAME} -a ${DOCKERBUILD_ARGS})
