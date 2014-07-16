# Set of firms
set N;

# Parameters of  linear inverse demand function
# P = a-b*Q
param a;
param b;

param c{N};  # constant marginal cost of each firm
param k{N};  # maximum production capacities of each firm

var q{N};    # quantities of each firm

var Q = sum{i in N} q[i]; # total output
var P = a-b*Q;            # price

# FOC of each company
# The FOC take into account the restrictions that 0<=q[i]<=k[i]
#  If pi' is the derivative of i's profits w.r.t. to q[i] the Kuhn-Tucker-Conditions are
#  i)		pi'=0 	and q[i] in (0, k[i]) or 
#  ii) 	pi'>=0	and q[i]=k[i] or
#  iii)	pi'<=0 	and q[i]=0
# 
#  This is a mixed complementarity problem and formulated as follows in AMPL
subject to FOC {i in N}: 
	0 <= q[i] <= k[i] complements 
	-(P-c[i] - b*(q[i]));

# Note that the last line is -pi'. That is becasue by default  two-side complementarity 
# problems  in AMPL are formulated such that the expression that is zero in an interior
# solution is positive at the lower bound and negative at the upper bound.
