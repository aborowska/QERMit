function d = MLtarget_WN_hl(eps, sigma2_mle, VaR_prelim)
    H = size(eps,2);
    
    prior =  prior_WN_hl(eps, sigma2_mle, VaR_prelim); 
    d = prior(:,2) - 0.5*(H*log(2*pi) + sum(eps.^2,2));
end

function R = prior_WN_hl(eps,sigma2_mle, VaR_prelim)
    N = size(eps,1);

    r1 = (fn_PL(sigma2_mle.*eps) <= VaR_prelim);   
    r2 = -Inf*ones(N,1);
    r2(r1==1,1) = 0;
    
    R = [r1, r2];
end