#!/bin/bash
# Copie este arquivo para run.sh e preencha suas credenciais:
#   cp run.example.sh run.sh

GEMINI_KEY="SUA_GEMINI_KEY_AQUI"
NEON_CONNECTION_STRING="postgresql://usuario:senha@host/banco?sslmode=require"

flutter run -d linux \
  --dart-define=GEMINI_KEY=$GEMINI_KEY \
  "--dart-define=NEON_CONNECTION_STRING=$NEON_CONNECTION_STRING"
