#!/usr/bin/env bash
#
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

cd $(git rev-parse --show-toplevel)
source $(dirname $0)/../vendor/github.com/tektoncd/plumbing/scripts/verified-catalog-e2e-common.sh

if [[ -z ${@} || ${1} == "-h" ]];then
    echo_local_test_helper_info
    exit 0
fi

set -x
set -e

TASK=${1}

TMPF=$(mktemp /tmp/.mm.XXXXXX)
clean() { rm -f ${TMPF}; }
trap clean EXIT

TMPD=$(mktemp -d /tmp/.mm.XXXXXX)
clean() { rm -f -r ${TMPD} ;}
trap clean EXIT

TEST_RUN_NIGHTLY_TESTS=""

taskdir="task/${TASK}"

[[ ${2} == "--nightly" ]] && TEST_RUN_NIGHTLY_TESTS=1

convert_directory_structure

cd ${TMPD}

test_yaml_can_install task/${TASK}/*/tests

test_task_creation task/${TASK}/*/tests

echo 'Success'