#!/usr/bin/env python

from flask import Flask, request, jsonify
from pprint import pprint
import base64
import copy
import json
import jsonpatch
import os
import re
import sys

app = Flask(__name__)


@app.route('/healthz')
def alive():
    return "{'status': 'A very simple check returns.'}"


@app.route('/', methods=['POST'])
def webhook():
    allowed = True
    request_info = request.json
    modified_spec = copy.deepcopy(request_info)
    uid = modified_spec["request"]["uid"]
    workload_metadata = modified_spec["request"]["object"]["metadata"]
    workload_type = modified_spec["request"]["kind"]["kind"]
    namespace = modified_spec["request"]["namespace"]
    tier = workload_metadata['labels'].get('dominodatalab.com/hardware-tier-id')

    print(f"Processing {workload_type} in namespace {namespace} tier {tier}")

    if workload_type == "Ingress" and namespace == NAMESPACE:
        add_ingress_tls(modified_spec)

    print("[INFO] - Diffing original request to modified request and generating JSONPatch")

    patch = jsonpatch.JsonPatch.from_diff(request_info["request"]["object"], modified_spec["request"]["object"])

    print("[INFO] - JSON Patch: {}".format(patch))

    admission_response = {
        "allowed": True,
        "uid": request_info["request"]["uid"],
        "patch": base64.b64encode(str(patch).encode()).decode(),
        "patchtype": "JSONPatch"
    }
    admissionReview = {
        "response": admission_response
    }

    print("[INFO] - Sending Response to K8s API Server:")
    pprint(admissionReview)
    return jsonify(admissionReview)


def add_ingress_tls(modified_spec):
    if 'kubernetes.io/ingress.allow-http' not in modified_spec['request']['object']['metadata']['annotations']:
        modified_spec['request']['object']['metadata']['annotations']["kubernetes.io/ingress.allow-http"] = 'false'

    if 'tls' not in modified_spec['request']['object']['spec']:
        modified_spec['request']['object']['spec']['tls'] = [{"hosts": [HOST, "*." + HOST], "secretName": SECRET}]


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Launch Mutating Webhook.')
    parser.add_argument('tls_secret',
                        help='TLS secret, of the format namespace/secret_name (required)')
    parser.add_argument('host',
                        help='Hostname to apply secret (required)')
    parser.add_argument('namespace', default="domino-compute",
                        help='Namespace of compute jobs, defaults to domino-compute.')

    args = parser.parse_args()
    HOST = args.host
    SECRET = args.tls_secret
    NAMESPACE = args.namespace
    print(
        'Applying webhook for host: {}, secret: {}, namespace: {}'.format(HOST, SECRET, NAMESPACE))
    app.run(host='0.0.0.0', port=5000, debug=True, ssl_context=('/ssl/cert.pem', '/ssl/key.pem'))
