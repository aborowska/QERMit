function d = posterior_arch_noS(theta, data, L)
    % alpha is Nx1, vector of draws
    N = size(theta,1);
    omega = theta(:,1);
    alpha = theta(:,2);
    
    prior = prior_arch(omega, alpha, L);
    T = length(data);
    ind = 2:T;
    
    d = -Inf*ones(N,1);
    h = zeros(T,1);
    h(1,1) = var(data);

    for ii = 1:N
        pdf = zeros(T,1);
        if (prior(ii,1)) % when all the parameter constraints are satisfied
            h(ind) =  omega(ii,1) + alpha(ii,1)*(data(ind-1,1)).^2;
            pdf(ind) = -0.5*(log(2*pi) + log(h(ind)) + (data(ind).^2)./h(ind));
%             for jj = 2:T
% %                 h(jj,1) = omega(ii,1) + alpha(ii,1)*(data(jj-1,1))^2;
%                 pdf(jj,1) = log(normpdf(data(jj,1),0,sqrt(h(jj,1))));
%             end
            d(ii,1) = sum(pdf) + prior(ii,2); 
        end
    end
    if (~L)
        d = exp(d);
    end
end


function R = prior_arch(omega, alpha, L)
    % uniform prior on a parameter alpha on [0,1)
    % prior is an Nx2 matrix: 
    % 1 col - constraint satisfied?
    % 2 col - prior val an the corresponding point
    c1 = ((alpha >= 0) & (alpha < 1));
    c2 = (omega > 0);
    r1 = c1 & c2;
    r2 = -Inf*ones(length(alpha),1);
    r2(r1==true) = 1;
    if (~L)
        r2 = exp(r2);
    end
    R = [r1, r2];
end
