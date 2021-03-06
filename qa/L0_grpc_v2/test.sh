#!/bin/bash
# Copyright (c) 2019-2020, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set +e

RET=0

# Install client dependencies
(apt-get update && \
    ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && \
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y tzdata && \
    dpkg-reconfigure --frontend noninteractive tzdata && \
    apt-get install -y --no-install-recommends \
        libopencv-dev \
        libopencv-core-dev \
        pkg-config \
        python3 \
        python3-pip \
        python3-dev \
        rapidjson-dev && \
    rm -f /usr/bin/python && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    pip3 install numpy && \
    pip3 install --upgrade wheel setuptools && \
    pip3 install --upgrade grpcio-tools)
if [ $? -eq 0 ]; then
    echo -e "\n***\n*** Dependency install Passed\n***"
else
    echo -e "\n***\n*** Dependency install Failed\n***"
    exit 1
fi

# Build Server and clients with gRPC V2 Support
(cd /workspace/builddir && \
    rm -fr trtis trtis-clients && \
    cmake -DCMAKE_BUILD_TYPE=Release \
        -DTRTIS_ENABLE_METRICS=OFF \
        -DTRTIS_ENABLE_METRICS_GPU=OFF \
        -DTRTIS_ENABLE_GCS=OFF \
        -DTRTIS_ENABLE_S3=OFF \
        -DTRTIS_ENABLE_CUSTOM=ON \
        -DTRTIS_ENABLE_TENSORRT=OFF \
        -DTRTIS_ENABLE_TENSORFLOW=ON \
        -DTRTIS_ENABLE_CAFFE2=OFF \
        -DTRTIS_ENABLE_ONNXRUNTIME=OFF \
        -DTRTIS_ENABLE_ONNXRUNTIME_OPENVINO=OFF \
        -DTRTIS_ENABLE_PYTORCH=OFF \
        -DTRTIS_ENABLE_GPU=OFF \
        -DTRTIS_ENABLE_GRPC=ON \
        -DTRTIS_ENABLE_HTTP=ON \
        -DTRTIS_ENABLE_GRPC_V2=ON \
        ../build && \
    make -j16 trtis trtis-clients && \
    cp -r trtis/install/bin /opt/tensorrtserver/. && \
    cp -r trtis/install/lib /opt/tensorrtserver/. && \
    cp -r trtis/install/include /opt/tensorrtserver/include/trtserver)

# install the tensorrtserver wheel file
pip3 install /workspace/builddir/trtis-clients/install/python/tensorrtserverV2-*.whl

if [ $? -eq 0 ]; then
    echo -e "\n***\n*** GRPC V2 Build Passed\n***"
else
    echo -e "\n***\n*** GRPC V2 Build Failed\n***"
    exit 1
fi


SIMPLE_V2_CLIENT=/workspace/builddir/trtis-clients/install/python/simple_grpc_pyclient_v2.py

rm -f *.log
(rm -fr models && mkdir models && \
    cp -r /workspace/docs/examples/model_repository/simple models/.)
CLIENT_LOG=`pwd`/client.log
DATADIR=`pwd`/models
SERVER=/opt/tensorrtserver/bin/trtserver
SERVER_ARGS="--model-repository=$DATADIR --api-version 2"
source ../common/util.sh

# FIXMEPV2
# Cannot use run_server since it repeatedly curls the (old) HTTP health endpoint to know
# when the server is ready. This endpoint would not exist in future.
run_server_nowait
sleep 10
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

python $SIMPLE_V2_CLIENT -v >> $CLIENT_LOG 2>&1
if [ $? -ne 0 ]; then
    cat $CLIENT_LOG
    RET=1
fi

if [ $(cat $CLIENT_LOG | grep "PASS" | wc -l) -ne 9 ]; then
    cat $CLIENT_LOG
    RET=1
fi

kill $SERVER_PID
wait $SERVER_PID

set -e

if [ $RET -eq 0 ]; then
    echo -e "\n***\n*** Test Passed\n***"
else
    echo -e "\n***\n*** Test FAILED\n***"
fi

exit $RET
