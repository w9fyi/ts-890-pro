#!/bin/bash
#
# cloud_train.sh — Upload data, train RNNoise on a Vast.ai instance,
#                  and download the trained model.
#
# Usage:
#   ./cloud_train.sh <vast-instance-ip> <port>
#
# Prerequisites:
#   1. Sign up at vast.ai and add credit ($10 minimum)
#   2. Rent a GPU instance (RTX 3090 or better, PyTorch/TF image)
#   3. Copy your SSH key: vast copy-ssh-key <instance-id>
#   4. Have denoise_data.h5 ready in this directory
#
# The script will:
#   - Upload training files and dataset
#   - Install pinned dependencies
#   - Run training with checkpoint saves
#   - Download the final model and training log

set -euo pipefail

HOST="${1:?Usage: $0 <instance-ip> <port>}"
PORT="${2:?Usage: $0 <instance-ip> <port>}"
SSH="ssh -p $PORT root@$HOST"
SCP="scp -P $PORT"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/denoise_data.h5"
OUTPUT_DIR="${SCRIPT_DIR}/cloud_output"

if [ ! -f "$DATA_FILE" ]; then
    echo "Error: denoise_data.h5 not found in ${SCRIPT_DIR}"
    echo "Generate it locally first, then place it in the training/ directory."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "=== Uploading training files ==="
$SCP "$SCRIPT_DIR/rnn_train.py" \
     "$SCRIPT_DIR/requirements.txt" \
     "root@$HOST:/root/"

echo "=== Uploading dataset (this may take a moment) ==="
$SCP "$DATA_FILE" "root@$HOST:/root/"

echo "=== Installing dependencies ==="
$SSH "pip install -r /root/requirements.txt"

echo "=== Starting training ==="
$SSH "cd /root && python3 rnn_train.py \
    --data denoise_data.h5 \
    --epochs 200 \
    --batch-size 32 \
    --output-dir /root/output"

echo "=== Downloading results ==="
$SCP "root@$HOST:/root/output/newweights.hdf5" "$OUTPUT_DIR/"
$SCP "root@$HOST:/root/output/training_log.csv" "$OUTPUT_DIR/"

# Grab any checkpoints too
$SCP "root@$HOST:/root/output/rnnoise_epoch*.hdf5" "$OUTPUT_DIR/" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Final model:  ${OUTPUT_DIR}/newweights.hdf5"
echo "Training log: ${OUTPUT_DIR}/training_log.csv"
echo ""
echo "Next steps:"
echo "  1. Review training_log.csv for loss convergence"
echo "  2. Convert weights to rnn_data.c for the C inference engine"
echo "  3. Rebuild TS-890 Pro with updated weights"
