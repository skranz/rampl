# Set of firms
set N;

# Parameters of  linear inverse demand function
# P = a-b*Q
param a;
param b;
param c{N};  # constant marginal cost of each firm

var q{N};    # quantities of each firm
var Q = sum{i in N} q[i]; # total output
var P = a-b*Q;            # price

# FOC of each company (ignoring q[i]>=0 constraint)
subject to FOC {i in N}: 
	(P-c[i] - b*(q[i]))==0;