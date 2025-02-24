#!/bin/bash

echo "Successful builds being tested: ${SUCCESS_BUILDERS}"

FAILED_TEST_BUILDS=()

packer build \
    -only "${SUCCESS_BUILDERS//amazon-ebssurrogate./amazon-ebs.}" \
    -var "spel_identifier=${SPEL_IDENTIFIER:?}" \
    -var "spel_version=${SPEL_VERSION:?}" \
    tests/minimal-linux.pkr.hcl | tee packer_test_output.log

TESTEXIT=$?

if [[ $TESTEXIT -ne 0 ]]; then
    FAILED_TEST_BUILDS+=($(grep -oP '(?<=Build ).*(?= errored)' packer_test_output.log | sed "s/'//g" | paste -sd ','))
    echo "ERROR: Test failed for builders: ${FAILED_TEST_BUILDS[*]}"
fi
