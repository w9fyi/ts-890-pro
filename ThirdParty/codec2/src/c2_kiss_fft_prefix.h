/* Rename codec2's kiss_fft symbols to avoid collision with ft8_lib/rnnoise copies */
#ifndef C2_KISS_FFT_PREFIX_H
#define C2_KISS_FFT_PREFIX_H
#define kiss_fft_alloc           c2_kiss_fft_alloc
#define kiss_fft                 c2_kiss_fft
#define kiss_fft_stride          c2_kiss_fft_stride
#define kiss_fft_cleanup         c2_kiss_fft_cleanup
#define kiss_fft_next_fast_size  c2_kiss_fft_next_fast_size
#define kiss_fftr_alloc          c2_kiss_fftr_alloc
#define kiss_fftr                c2_kiss_fftr
#define kiss_fftri               c2_kiss_fftri
#endif
