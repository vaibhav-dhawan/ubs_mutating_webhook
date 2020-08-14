#!/bin/bash
export PATH=$PATH:/home/app/.local/bin
pip install --user -r /app/requirements.txt
/app/webhook.py "$@"
