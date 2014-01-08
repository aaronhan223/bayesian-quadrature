# cython: profile=True

from numpy.linalg import LinAlgError
from numpy import array, empty, zeros
from numpy import float64, int32

import scipy.stats

######################################################################

from numpy cimport ndarray, float64_t, int32_t
from libc.math cimport sqrt, exp, log, fmax, copysign, fabs, M_PI
cimport linalg_c as la
cimport cython

######################################################################

@cython.boundscheck(False)
@cython.wraparound(False)
cpdef float64_t mvn_logpdf(float64_t[::1] x, float64_t[::1] m, float64_t[::1, :] L, float64_t logdet):
    """Computes the logpdf for a multivariate normal distribution:

    out = N(x | m, C)
        = -0.5 * (log(2*pi)*d + log(|C|) + (x-m)*C^-1*(x-m))

    """
    cdef int d = x.shape[0]
    cdef float64_t[::1] diff = empty(d, dtype=float64)
    cdef float64_t[::1] buf = empty(d, dtype=float64)
    cdef float64_t c = log(2 * M_PI) * d + logdet
    cdef float64_t out

    if m.shape[0] != d:
        la.value_error("m has invalid size")
    if L.shape[0] != d or L.shape[1] != d:
        la.value_error("C has invalid size")

    for i in xrange(d):
        diff[i] = x[i] - m[i]

    la.cho_solve_vec(L, diff, buf)
    out = -0.5 * (c + la.dot11(diff, buf))
    return out


cpdef float64_t int_exp_norm(float64_t c, float64_t m, float64_t S):
    """Computes integrals of the form:

    int exp(cx) N(x | m, S) = exp(cm + (1/2) c^2 S)

    """
    cdef float64_t out = exp((c * m) + (0.5 * c ** 2 * S))
    return out


@cython.boundscheck(False)
@cython.wraparound(False)
cpdef int_K(float64_t[::1] out, float64_t[::1, :] x, float64_t h, float64_t[::1] w, float64_t[::1] mu, float64_t[::1, :] cov):
    """Computes integrals of the form:

    int K(x', x) N(x' | mu, cov) dx'

    where K is a Gaussian kernel matrix parameterized by `h` and `w`.

    The result is:

    out[i] = h^2 N(x_i | mu, W + cov)

    """

    cdef int d = x.shape[0]
    cdef int n = x.shape[1]

    cdef float64_t[::1, :] W = empty((d, d), dtype=float64, order='F')

    cdef float64_t h_2 = h ** 2
    cdef float64_t logdet
    cdef int i, j

    if out.shape[0] != n:
        la.value_error("out has invalid shape")
    if w.shape[0] != d:
        la.value_error("w has invalid shape")
    if mu.shape[0] != d:
        la.value_error("mu has invalid shape")
    if cov.shape[0] != d or cov.shape[1] != d:
        la.value_error("cov has invalid shape")

    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                W[i, j] = cov[i, j] + w[i] ** 2
            else:
                W[i, j] = cov[i, j]

    la.cho_factor(W, W)
    logdet = la.logdet(W)

    for i in xrange(n):
        out[i] = h_2 * exp(mvn_logpdf(x[:, i], mu, W, logdet))

    return


@cython.boundscheck(False)
@cython.wraparound(False)
cpdef approx_int_K(float64_t[::1] out, float64_t[::1, :] xo, float64_t[::1, :] Kxxo, float64_t[::1] mu, float64_t[::1, :] cov):
    """
    out is (m,)
    xo is (d, n)
    Kxxo is (m, n)
    mu is (d,)
    cov is (d, d)
    """

    cdef int m = Kxxo.shape[0]
    cdef int d = xo.shape[0]
    cdef int n = xo.shape[1]

    cdef float64_t[::1, :] L = empty((d, d), dtype=float64)
    cdef float64_t[::1] p_xo = empty(n, dtype=float64)
    cdef float64_t[::1] diff = empty(n-1, dtype=float64)
    cdef float64_t logdet, Kp1, Kp2
    cdef int i, j

    if out.shape[0] != m:
        la.value_error("out has invalid shape")
    if Kxxo.shape[1] != n:
        la.value_error("Kxxo has invalid shape")
    if mu.shape[0] != d:
        la.value_error("mu has invalid shape")
    if cov.shape[0] != d or cov.shape[1] != d:
        la.value_error("mu has invalid shape")

    la.cho_factor(cov, L)
    logdet = la.logdet(L)

    for i in xrange(n):
        p_xo[i] = exp(mvn_logpdf(xo[:, i], mu, L, logdet))

    for i in xrange(n-1):
        diff[i] = la.vecdiff(xo[:, i+1], xo[:, i])

    # compute approximate integral with trapezoidal rule
    for i in xrange(m):
        out[i] = 0
        for j in xrange(n-1):
            Kp1 = Kxxo[i, j] * p_xo[j]
            Kp2 = Kxxo[i, j+1] * p_xo[j+1]
            out[i] += diff[j] * (Kp1 + Kp2) / 2.

    return


cpdef int_K1_K2(ndarray[float64_t, mode='fortran', ndim=2] out, ndarray[float64_t, mode='fortran', ndim=2] x1, ndarray[float64_t, mode='fortran', ndim=2] x2, float64_t h1, ndarray[float64_t, mode='fortran', ndim=1] w1, float64_t h2, ndarray[float64_t, mode='fortran', ndim=1] w2, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov):
    """Computes integrals of the form:

    int K_1(x1, x') K_2(x', x2) N(x' | mu, cov) dx'

    where K_1 is a Gaussian kernel matrix parameterized by `h1` and
    `w1`, and K_2 is a Gaussian kernel matrix parameterized by `h2`
    and `w2`.

    The result is:

    out[i, j] = h1^2 h2^2 N([x1_i, x2_j] | [mu, mu], [W1 + cov, cov; cov, W2 + cov])

    """
    
    cdef int n1 = x1.shape[0]
    cdef int n2 = x2.shape[0]
    cdef int d = x1.shape[1]

    cdef ndarray[float64_t, mode='fortran', ndim=3] x = empty((n1, n2, 2 * d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=1] m = empty(2 * d, dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] C = empty((2 * d, 2 * d), dtype=float64, order='F')

    cdef float64_t h1_2_h2_2 = (h1 ** 2) * (h2 ** 2)
    cdef float64_t logdet
    cdef int i, j, k

    if out.shape[0] != n1 or out.shape[0] != n2:
        la.value_error("out has invalid shape")
    if x2.shape[1] != d:
        la.value_error("x2 has invalid shape")
    if w1.shape[0] != d:
        la.value_error("w1 has invalid shape")
    if w2.shape[0] != d:
        la.value_error("w2 has invalid shape")
    if mu.shape[0] != d:
        la.value_error("mu has invalid shape")
    if cov.shape[0] != d or cov.shape[1] != d:
        la.value_error("cov has invalid shape")

    # compute concatenated means [mu, mu]
    for i in xrange(d):
        m[i] = mu[i]
        m[i + d] = mu[i]

    # compute concatenated covariances [W1 + cov, cov; cov; W2 + cov]
    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                C[i, j] = w1[i] ** 2 + cov[i, j]
                C[i + d, j + d] = w2[i] ** 2 + cov[i, j]
            else:
                C[i, j] = cov[i, j]
                C[i + d, j + d] = cov[i, j]

            C[i, j + d] = cov[i, j]
            C[i + d, j] = cov[i, j]

    # compute concatenated x
    for i in xrange(n1):
        for j in xrange(n2):
            for k in xrange(d):
                x[i, j, k] = x1[i, k]
                x[i, j, k + d] = x2[j, k]

    # compute cholesky factor and determinant
    la.cho_factor(C, C)
    logdet = la.logdet(C)

    # compute pdf
    for i in xrange(n1):
        for j in xrange(n2):
            out[i, j] = h1_2_h2_2 * exp(mvn_logpdf(x[i, j], m, C, logdet))

    return


# def approx_int_K1_K2(xo, gp1, gp2, mu, cov):
#     K1xxo = gp1.Kxxo(xo)
#     K2xxo = gp2.Kxxo(xo)
#     p_xo = scipy.stats.norm.pdf(xo, mu[0], np.sqrt(cov[0, 0]))
#     approx_int = np.trapz(K1xxo[:, None] * K2xxo[None, :] * p_xo, xo)
#     return approx_int


cpdef int_int_K1_K2_K1(ndarray[float64_t, mode='fortran', ndim=2] out, ndarray[float64_t, mode='fortran', ndim=2] x, float64_t h1, ndarray[float64_t, mode='fortran', ndim=1] w1, float64_t h2, ndarray[float64_t, mode='fortran', ndim=1] w2, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov):
    """Computes integrals of the form:

    int int K_1(x, x1') K_2(x1', x2') K_1(x2', x) N(x1' | mu, cov) N(x2' | mu, cov) dx1' dx2'

    where K_1 is a Gaussian kernel matrix parameterized by `h1` and
    `w1`, and K_2 is a Gaussian kernel matrix parameterized by `h2`
    and `w2`.

    The result is:

    out[i, j] = h1^4 h2^2 |G|^-1 N(x_i | mu, W1 + cov) N(x_j | mu, W1 + cov) N(x_i | x_j, G^-1 (W2 + 2*cov - 2*G*cov) G^-1)

    where G = cov(W1 + cov)^-1

    """

    cdef int n = x.shape[0]
    cdef int d = x.shape[1]

    cdef ndarray[float64_t, mode='fortran', ndim=2] W1_cov = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] L = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] A = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] B = empty((d, n), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] C = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=1] N1 = empty(n, dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] N2 = empty((n, n), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=1] buf = empty(d, dtype=float64, order='F')

    cdef float64_t h1_4_h2_2 = (h1 ** 4) * (h2 ** 2)
    cdef logdet
    cdef int i, j

    if out.shape[0] != n or out.shape[1] != n:
        la.value_error("out has invalid shape")
    if w1.shape[0] != d:
        la.value_error("w1 has invalid shape")
    if w2.shape[0] != d:
        la.value_error("w2 has invalid shape")
    if mu.shape[0] != d:
        la.value_error("mu has invalid shape")
    if cov.shape[0] != d or cov.shape[1] != d:
        la.value_error("cov has invalid shape")

    # compute W1 + cov
    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                W1_cov[i, j] = cov[i, j] + w1[i] ** 2
            else:
                W1_cov[i, j] = cov[i, j]

    # compute A = cov*(W1 + cov)^-1*cov
    la.cho_factor(W1_cov, L)
    logdet = la.logdet(L)
    la.cho_solve_mat(L, cov, W1_cov)
    la.dot22(cov, W1_cov, A)

    # compute B = cov*(W1 + cov)^-1 * x
    for i in xrange(n):
        la.cho_solve_vec(L, x[i], buf)
        la.dot21(cov, buf, B[:, i])

    # compute N1 = N(x | mu, W1 + cov)
    for i in xrange(n):
        N1[i] = mvn_logpdf(x[i], mu, L, logdet)

    # compute C = W2 + 2*cov - 2*cov*(W1 + cov)^-1*cov
    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                C[i, j] = w2[i] ** 2 + 2*cov[i, j] - 2*A[i, j]
            else:
                C[i, j] = 2*cov[i, j] - 2*A[i, j]

    # compute N2 = N(cov*(W1 + cov)^-1 * x_i | cov*(W1 + cov)^-1 * x_j, C)
    la.cho_factor(C, L)
    logdet = la.logdet(L)
    for i in xrange(n):
        for j in xrange(n):
            N2[i, j] = mvn_logpdf(B[i], B[j], L, logdet)

    # put it all together
    for i in xrange(n):
        for j in xrange(n):
            out[i, j] = h1_4_h2_2 * exp(N1[i] + N1[j] + N2[i, j])

    return


# def approx_int_int_K1_K2_K1(xo, gp1, gp2, mu, cov):
#     K1xxo = gp1.Kxxo(xo)
#     K2xoxo = gp2.Kxoxo(xo)
#     p_xo = scipy.stats.norm.pdf(xo, mu[0], np.sqrt(cov[0, 0]))
#     int1 = np.trapz(K1xxo[:, None, :] * K2xoxo * p_xo, xo)
#     approx_int = np.trapz(K1xxo[:, None] * int1[None] * p_xo, xo)
#     return approx_int


cpdef int_int_K1_K2(ndarray[float64_t, mode='fortran', ndim=1] out, ndarray[float64_t, mode='fortran', ndim=2] x, float64_t h1, ndarray[float64_t, mode='fortran', ndim=1] w1, float64_t h2, ndarray[float64_t, mode='fortran', ndim=1] w2, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov):
    """Computes integrals of the form:

    int int K_1(x2', x1') K_2(x1', x) N(x1' | mu, cov) N(x2' | mu, cov) dx1' dx2'

    where K_1 is a Gaussian kernel matrix parameterized by `h1` and
    `w1`, and K_2 is a Gaussian kernel matrix parameterized by `h2`
    and `w2`.

    The result is:

    out[i] = h1^2 h2^2 N(0 | 0, W1 + 2*cov) N(x_i | mu, W2 + cov - cov*(W1 + 2*cov)^-1*cov)

    """

    cdef int n = x.shape[0]
    cdef int d = x.shape[1]

    cdef ndarray[float64_t, mode='fortran', ndim=2] W1_2cov = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] C = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] buf = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=1] N2 = empty(n, dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=1] z = zeros(d, dtype=float64, order='F')

    cdef float64_t h1_2_h2_2 = (h1 ** 2) * (h2 ** 2)
    cdef float64_t N1, logdet
    cdef int i, j

    if out.shape[0] != n:
        la.value_error("out has invalid shape")
    if w1.shape[0] != d:
        la.value_error("w1 has invalid shape")
    if w2.shape[0] != d:
        la.value_error("w2 has invalid shape")
    if mu.shape[0] != d:
        la.value_error("mu has invalid shape")
    if cov.shape[0] != d or cov.shape[1] != d:
        la.value_error("cov has invalid shape")

    # compute W1 + 2*cov
    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                W1_2cov[i, j] = 2*cov[i, j] + w1[i] ** 2
            else:
                W1_2cov[i, j] = 2*cov[i, j]

    # compute N(0 | 0, W1 + 2*cov)
    la.cho_factor(W1_2cov, W1_2cov)
    N1 = mvn_logpdf(z, z, W1_2cov, la.logdet(W1_2cov))

    # compute C = cov*(W1 + 2*cov)^-1*cov
    la.cho_solve_mat(W1_2cov, cov, buf)
    la.dot22(cov, buf, C)

    # compute W2 + cov - cov*(W1 + 2*cov)^-1*cov
    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                C[i, j] = w2[i] ** 2 + cov[i, j] - C[i, j]
            else:
                C[i, j] = cov[i, j] - C[i, j]

    # compute N(x | mu, W2 + cov - cov*(W1 + 2*cov)^-1*cov)
    la.cho_factor(C, C)
    logdet = la.logdet(C)
    for i in xrange(n):
        N2[i] = mvn_logpdf(x[i], mu, C, logdet)

    for i in xrange(n):
        out[i] = h1_2_h2_2 * exp(N1 + N2[i])

    return


# def approx_int_int_K1_K2(xo, gp1, gp2, mu, cov):
#     K1xoxo = gp1.Kxoxo(xo)
#     K2xxo = gp2.Kxxo(xo)
#     p_xo = scipy.stats.norm.pdf(xo, mu[0], np.sqrt(cov[0, 0]))
#     int1 = np.trapz(K1xoxo * K2xxo[:, :, None] * p_xo, xo)
#     approx_int = np.trapz(int1 * p_xo, xo)
#     return approx_int


cpdef float64_t int_int_K(int32_t d, float64_t h, ndarray[float64_t, mode='fortran', ndim=1] w, ndarray[float64_t, mode='fortran', ndim=1] mu, ndarray[float64_t, mode='fortran', ndim=2] cov):
    """Computes integrals of the form:

    int int K(x1', x2') N(x1' | mu, cov) N(x2' | mu, cov) dx1' dx2'

    where K is a Gaussian kernel parameterized by `h` and `w`.

    The result is:

    out = h^2 N(0 | 0, W + 2*cov)

    """

    cdef ndarray[float64_t, mode='fortran', ndim=2] W_2cov = empty((d, d), dtype=float64, order='F')
    cdef ndarray[float64_t, mode='fortran', ndim=2] z = zeros(d, dtype=float64, order='F')
    cdef int i, j

    if w.shape[0] != d:
        la.value_error("w has invalid shape")
    if mu.shape[0] != d:
        la.value_error("mu has invalid shape")
    if cov.shape[0] != d or cov.shape[1] != d:
        la.value_error("cov has invalid shape")

    # compute W + 2*cov
    for i in xrange(d):
        for j in xrange(d):
            if i == j:
                W_2cov[i, j] = 2*cov[i, j] + w[i] ** 2
            else:
                W_2cov[i, j] = 2*cov[i, j]

    # compute N(0 | 0, W1 + 2*cov)
    la.cho_factor(W_2cov, W_2cov)

    return (h ** 2) * exp(mvn_logpdf(z, z, W_2cov, la.logdet(W_2cov)))


# def approx_int_int_K(xo, gp, mu, cov):
#     Kxoxo = gp.Kxoxo(xo)
#     p_xo = scipy.stats.norm.pdf(xo, mu[0], np.sqrt(cov[0, 0]))
#     approx_int = np.trapz(np.trapz(Kxoxo * p_xo, xo) * p_xo, xo)
#     return approx_int
