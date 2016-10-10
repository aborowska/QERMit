function [theta, x, lnw, lnk, lng_y, lnw_x, eps_bar, eps_sim, C_T, lnp_T, RND, ind, accept] = EMit_MH_new(N, d, kernel, mit, GamMat, MH)
% sample N draws from mixture of t's mit and evaluate them on the kernel
% if MH = true then also perform independence MH on the drawn sample
% with using mit as the candidate density
% input:
% N - lenght of the generated chain
% d - dimension of the distribution
% kernel - function which computes the kernel
% mit - mixture of t's
% output:
% theta - [Nxd] matrix of samples generated by the independence MH (or just drawm from mit)
% accept - acceptance rate in the independence MH
    resampl_on = false;

    if (N <= 2000)
        [theta, lnk, ~, x, lng_y, lnw_x, eps_bar, eps_sim, C_T, lnp_T, RND] = fn_rmvgt_robust(N, mit, kernel, resampl_on, theta);
    else
        theta = zeros(N, d);
        lnk = zeros(N,1);
        lng_y = zeros(N,1);
        lnw_x = zeros(N,1);
        eps_bar = zeros(N,1);
        eps_sim = zeros(N,1);
        C_T = zeros(N,1);
        lnp_T = zeros(N,1);
        RND = zeros(N,1);
        for ii = 1:(N/1000)
            fprintf('Sampling ii = %i\n',ii)
            ind = (1:1000) + (ii-1)*1000;
            if (ii == 1)
                [theta(ind,:), lnk(ind,:), ~, x, lng_y(ind,:), lnw_x(ind,:), eps_bar(ind,:), eps_sim(ind,:), C_T(ind,:), lnp_T(ind,:), RND(ind,:)] = fn_rmvgt_robust(1000, mit, kernel, resampl_on, theta(ind,:));      
                HP = size(x,2);
                x = [x; zeros(N - 1000, HP)];
            else
                [theta(ind,:), lnk(ind,:), ~, x(ind,:), lng_y(ind,:), lnw_x(ind,:), eps_bar(ind,:), eps_sim(ind,:), C_T(ind,:), lnp_T(ind,:), RND(ind,:)] = fn_rmvgt_robust(1000, mit, kernel, resampl_on, theta(ind,:));      
            end
        end
    end
    
    ind_real = ((imag(lnk)==0) & ~isnan(lnk));
    lnk(~ind_real) = -Inf;
    
    lnd = dmvgt(theta, mit, true, GamMat);
    lnw = lnk - lnd;
    lnw = lnw - max(lnw);
    
    if MH
        fprintf('MH running...\n')
        [ind, a] = fn_MH(lnw);
        accept = a/N;   
        
        theta = theta(ind,:);
        lnw = lnw(ind,:);
        lnk = lnk(ind,:);
        x = x(ind,:);
        lng_y = lng_y(ind,:);
        lnw_x = lnw_x(ind,:);
        eps_bar = eps_bar(ind,:);
        eps_sim = eps_sim(ind,:);
        C_T = C_T(ind,:);
        lnp_T = lnp_T(ind,:);
        RND = RND(ind,:);
    else 
        accept = 100;
        ind = 1:N;
    end       
end