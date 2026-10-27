"""Independent stdlib Decimal oracle: at most 64 tiny fixed-state cases.

Precision is pinned to 80 decimal digits. Shapes are positive integer or half
integer and at most 32. No target dimension, full prior reconstruction, or
optimizer is implemented. The original RHS prior scalar is an explicit shared
boundary; this oracle does not independently verify that scalar's R evaluation.
"""
from decimal import Decimal as D, localcontext

PRECISION = 80
PI = D('3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679')
EULER = D('0.5772156649015328606065120900824024310421593359399235988057672348848677267776646709369470632917467495')


def dec(x):
    if isinstance(x, D):
        return x
    if isinstance(x, float):
        return D.from_float(x)
    return D(x)


def gamma_pair(x):
    """log Gamma and digamma by exact recurrence from 1 or 1/2."""
    x = dec(x)
    if x <= 0 or x > 32 or x * 2 != (x * 2).to_integral_value():
        raise ValueError('oracle shape outside tiny integer/half-integer domain')
    if x == x.to_integral_value():
        z = D(1); lg = D(0); psi = -EULER
    else:
        z = D('.5'); lg = PI.ln()/2; psi = -EULER-2*D(2).ln()
    while z < x:
        lg += z.ln(); psi += 1/z; z += 1
    return lg, psi


def solve(P, b):
    if not 1 <= len(b) <= 4 or len(P) != len(b):
        raise ValueError('oracle Gaussian dimension outside 1..4')
    with localcontext() as ctx:
        ctx.prec = PRECISION
        p=len(b); A=[[dec(x) for x in row] for row in P]; rhs=list(map(dec,b))
        if any(len(row)!=p for row in A) or any(A[i][j]!=A[j][i] for i in range(p) for j in range(p)):
            raise ValueError('non-symmetric oracle input')
        L=[[D(0)]*p for _ in range(p)]
        for i in range(p):
            for j in range(i+1):
                value=A[i][j]-sum((L[i][k]*L[j][k] for k in range(j)),D(0))
                if i==j:
                    if value<=0: raise ValueError('non-SPD oracle input')
                    L[i][j]=value.sqrt()
                else: L[i][j]=value/L[j][j]
        def one(v):
            y=[]
            for i in range(p): y.append((v[i]-sum((L[i][j]*y[j] for j in range(i)),D(0)))/L[i][i])
            x=[D(0)]*p
            for i in reversed(range(p)):
                x[i]=(y[i]-sum((L[j][i]*x[j] for j in range(i+1,p)),D(0)))/L[i][i]
            return x
        beta=one(rhs)
        columns=[one([D(int(i==j)) for i in range(p)]) for j in range(p)]
        return beta, [[columns[j][i] for j in range(p)] for i in range(p)]


def objective(residual, second, sigma, tau, p, logdetV, prior_elbo):
    if not 1 <= len(residual) <= 8 or not 1 <= p <= 4 or len(second)!=len(residual):
        raise ValueError('oracle objective outside n<=8,p<=4')
    with localcontext() as ctx:
        ctx.prec=PRECISION
        r=list(map(dec,residual)); q=list(map(dec,second))
        sig=dec(sigma); t=dec(tau); prior=dec(prior_elbo)
        if sig<=0 or not 0<t<1 or any(x<0 for x in q): raise ValueError('invalid oracle input')
        n=D(len(r)); a=1+D('1.5')*n; b=sig*(a-1); k=a/b
        A=(1-2*t)/(t*(1-t)); B=2/(t*(1-t)); lg,psi_a=gamma_pair(a)
        chi=[max(k/B*v,D('1e-12')) for v in q]; ps=max(k*(2+A*A/B),D('1e-12'))
        ell=[(ps/x).sqrt() for x in chi]
        nu=[(x/ps).sqrt()*(1+1/(x*ps).sqrt()) for x in chi]
        # Expanded source formula at shape1/2, deliberately not the production
        # collapsed formula. Elog has any finite value because the identical
        # vector cancels symbolically between likelihood and entropy.
        elog=[(x.ln()-ps.ln())/2 for x in chi]
        logK=[(PI/(2*(x*ps).sqrt())).ln()/2-(x*ps).sqrt() for x in chi]
        logc=[(ps.ln()-x.ln())/4-D(2).ln()-v for x,v in zip(chi,logK)]
        Hlatent=sum((-lc+ev/2+(x*el+ps*nv)/2 for lc,ev,x,el,nv in zip(logc,elog,chi,ell,nu)),D(0))
        elogs=b.ln()-psi_a
        Hbeta=(D(p)*(1+(2*PI).ln())+dec(logdetV))/2
        Hsigma=a+b.ln()+lg-(a+1)*psi_a
        quad=sum((el*v-2*A*rr+A*A*nv for el,v,rr,nv in zip(ell,q,r,nu)),D(0))
        answer=prior-2*elogs-k-n*elogs-k*sum(nu,D(0))
        answer-=n/2*((2*PI).ln()+B.ln()+elogs)
        answer-=sum(elog,D(0))/2+k/(2*B)*quad
        answer+=Hbeta+Hsigma+Hlatent
        return +answer
