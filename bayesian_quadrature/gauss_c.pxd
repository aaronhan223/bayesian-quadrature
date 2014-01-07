from numpy cimport ndarray, float64_t, int32_t

cpdef float64_t mvn_logpdf(ndarray[float64_t, mode='fortran', ndim=1] x, ndarray[float64_t, mode='fortran', ndim=1] m, ndarray[float64_t, mode='fortran', ndim=2] L, float64_t logdet)
cpdef float64_t int_exp_norm(float64_t c, float64_t m, float64_t S)
cpdef int_K(ndarray[float64_t, mode='fortran', ndim=1] out, ndarray[float64_t, mode='fortran', ndim=2] x, float64_t h, ndarray[float64_t, mode='fortran', ndim=1] w, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov)
cpdef int_K1_K2(ndarray[float64_t, mode='fortran', ndim=2] out, ndarray[float64_t, mode='fortran', ndim=2] x1, ndarray[float64_t, mode='fortran', ndim=2] x2, float64_t h1, ndarray[float64_t, mode='fortran', ndim=1] w1, float64_t h2, ndarray[float64_t, mode='fortran', ndim=1] w2, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov)
cpdef int_int_K1_K2_K1(ndarray[float64_t, mode='fortran', ndim=2] out, ndarray[float64_t, mode='fortran', ndim=2] x, float64_t h1, ndarray[float64_t, mode='fortran', ndim=1] w1, float64_t h2, ndarray[float64_t, mode='fortran', ndim=1] w2, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov)
cpdef int_int_K1_K2(ndarray[float64_t, mode='fortran', ndim=1] out, ndarray[float64_t, mode='fortran', ndim=2] x, float64_t h1, ndarray[float64_t, mode='fortran', ndim=1] w1, float64_t h2, ndarray[float64_t, mode='fortran', ndim=1] w2, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov)
cpdef float64_t int_int_K(int32_t d, float64_t h, ndarray[float64_t, mode='fortran', ndim=1] w, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov)
