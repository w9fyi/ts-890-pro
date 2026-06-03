#!/usr/bin/env python3
"""
RNNoise training script for TS-890 Pro noise reduction.

Trains a GRU-based model to estimate per-band gains for noise suppression.
Input: 22 Bark-scale band features per frame
Output: 22 gain values (0-1) applied to noisy spectrum

Designed to run locally or on a cloud GPU (Vast.ai, Lambda, etc.).
Saves checkpoints every 10 epochs so training survives interruptions.
"""

import argparse
import os
import sys

from keras.models import Model
from keras.layers import Input, GRU, Dense
from keras.callbacks import ModelCheckpoint, CSVLogger
from keras import backend as K
import h5py
import numpy as np


def build_model():
    main_input = Input(shape=(None, 22), name='main_input')
    x = GRU(128, activation='tanh', recurrent_activation='sigmoid',
            return_sequences=True)(main_input)
    x = Dense(22, activation='sigmoid')(x)
    model = Model(inputs=main_input, outputs=x)
    model.compile(loss='mean_squared_error',
                  optimizer='adam',
                  metrics=['binary_accuracy'])
    return model


def load_data(data_path, window_size=500):
    print(f'Loading data from {data_path}...')
    with h5py.File(data_path, 'r') as hf:
        all_data = hf['denoise_data'][:]
    print('done.')

    nb_sequences = len(all_data) // window_size
    print(f'{nb_sequences} sequences')

    x_train = all_data[:nb_sequences * window_size, :-22]
    x_train = np.reshape(x_train, (nb_sequences, window_size, 22))

    y_train = np.copy(all_data[:nb_sequences * window_size, -22:])
    y_train = np.reshape(y_train, (nb_sequences, window_size, 22))

    # Free raw data
    all_data = None

    x_train = x_train.astype('float32')
    y_train = y_train.astype('float32')

    print(f'{len(x_train)} train sequences. '
          f'x shape = {x_train.shape}, y shape = {y_train.shape}')

    return x_train, y_train


def main():
    parser = argparse.ArgumentParser(description='Train RNNoise model')
    parser.add_argument('--data', default='denoise_data.h5',
                        help='Path to HDF5 training data')
    parser.add_argument('--epochs', type=int, default=200,
                        help='Number of training epochs')
    parser.add_argument('--batch-size', type=int, default=32,
                        help='Training batch size')
    parser.add_argument('--output-dir', default='.',
                        help='Directory for checkpoints and final model')
    parser.add_argument('--resume', default=None,
                        help='Path to checkpoint to resume from')
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    print('Building model...')
    model = build_model()

    if args.resume:
        print(f'Resuming from {args.resume}')
        model.load_weights(args.resume)

    x_train, y_train = load_data(args.data)

    # Save a checkpoint every 10 epochs
    checkpoint_path = os.path.join(
        args.output_dir, 'rnnoise_epoch{epoch:03d}.hdf5')
    checkpoint_cb = ModelCheckpoint(
        checkpoint_path,
        save_freq=10 * (len(x_train) // args.batch_size),
        save_weights_only=False,
        verbose=1
    )

    # Log training metrics to CSV for review
    log_path = os.path.join(args.output_dir, 'training_log.csv')
    csv_cb = CSVLogger(log_path, append=True)

    print('Training...')
    model.fit(
        x_train, y_train,
        batch_size=args.batch_size,
        epochs=args.epochs,
        validation_split=0.1,
        callbacks=[checkpoint_cb, csv_cb]
    )

    final_path = os.path.join(args.output_dir, 'newweights.hdf5')
    model.save(final_path)
    print(f'Final model saved to {final_path}')
    print(f'Training log at {log_path}')


if __name__ == '__main__':
    main()
