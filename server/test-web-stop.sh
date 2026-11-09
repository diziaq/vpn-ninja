#!/usr/bin/env bash
pkill -f "http.server 80"; pkill -f tls.py; rm -rf /root/probe; echo "TEST SERVER STOPPED"
