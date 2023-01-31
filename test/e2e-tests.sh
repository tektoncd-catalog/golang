#!/usr/bin/env bash

# Copyright 2023 The Tekton Authors
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

# Configure the number of parallel tests running at the same time, start from 0
MAX_NUMBERS_OF_PARALLEL_TASKS=7 # => 8

# Define this variable if you want to run tests for all releases of the catalog
TEST_RUN_NIGHTLY_TESTS=${TEST_RUN_NIGHTLY_TESTS:-""}

source $(dirname $0)/../vendor/github.com/tektoncd/plumbing/scripts/e2e-tests.sh
source $(dirname $0)/../vendor/github.com/tektoncd/plumbing/scripts/verified-catalog-e2e-common.sh

TMPF=$(mktemp /tmp/.mm.XXXXXX)
clean() { rm -f ${TMPF}; }
trap clean EXIT

TMPD=$(mktemp -d /tmp/.mm.XXXXXX)
clean() { rm -f -r ${TMPD} ;}
trap clean EXIT

# Install Tekton CRDs.
install_pipeline_crd

set -ex
set -o pipefail

convert_directory_structure

cd ${TMPD}

all_tests=$(echo task/*/*/tests)

test_yaml_can_install ${all_tests}

test_tasks ${all_tests}

success