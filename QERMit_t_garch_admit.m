%% Initialisation
clear all
close all
addpath(genpath('include/'));

% s = RandStream('mt19937ar','Seed',1);
% RandStream.setGlobalStream(s); 

v_new = ver('symbolic');
v_new = v_new.Release;
if strcmp(v_new,'(R2014b)')
    v_new = 1;
else
    v_new = 0;
end

x_gam = (0:0.00001:100)'+0.00001;
GamMat = gamma(x_gam);

% data = csvread('GSPC_ret_tgarch.csv');
% data = 100*data;
y = csvread('GSPC_ret.csv');
y = 100*y;
ind_arch = find(y<=-5.5, 1, 'last' );
y = y(1:ind_arch,1);
y = y - mean(y);
data = y;

T = size(data,1);
y_T = data(T);
S = var(data);
 
M = 10000;
N_sim = 100;

% L = true;
% hyper = 1;
% theta = [alpha, beta, mu, nu]
mu_init = [0.03, 0.9, 0.03, 6];

hp = 1; % prediction horizon 

algo = 'AdMit';
model = 't_garch';
    
plot_on = false;
print_on  = false;
plot_on2 = true;
save_on = true;


AdMit_Control
cont.IS.opt = true;
cont.IS.scale = [0.8, 1.0, 1.2]; 
cont.IS.perc = [0.25, 0.30, 0.35];
cont.resmpl_on = true;

cont2 = cont;
cont2.IS.opt = true; 
cont2.Hmax = 2;
cont2.dfnc = 5;
cont2.IS.scale = [1.0]; 
cont2.IS.perc = [0.25];

t_garch_plot0;

%  p_bar = 0.01;
% P_bars = [0.01, 0.05, 0.1, 0.5];
P_bars = 0.01;

VaR_prelim = zeros(N_sim,1);
VaR_prelim_MC = zeros(N_sim,length(P_bars));
ES_prelim = zeros(N_sim,length(P_bars));
accept = zeros(N_sim,length(P_bars));

VaR_IS = zeros(N_sim,length(P_bars));
ES_IS = zeros(N_sim,length(P_bars));

for p_bar = P_bars
    fprintf('\np_bar: %4.2f\n',p_bar);
    %% QERMit 1a.:
    kernel_init = @(a) - posterior_t_garch_mex(a, data , S, GamMat);
    kernel = @(a) posterior_t_garch_mex(a, data, S, GamMat);
    % kernel_init = @(a) - posterior_t_garch(a, data, S, L, hyper, GamMat);
    % kernel = @(a) posterior_t_garch(a, data, S, L, hyper, GamMat);
    % kernel(mu_init)
    [mit1, summary1] = AdMit(kernel_init, kernel, mu_init, cont, GamMat);
    t_garch_plot1;

    for sim = 1:N_sim  
    %     [mit1, summary1] = AdMit(kernel_init, kernel, mu_init, cont, GamMat);

        %% QERMit 1b.:
        % generate set opf draws of theta using independence MH with
        % candiate from MitISEM; then simulate returns based on the draw of theta 
        [theta1, accept(sim,P_bars==p_bar)] = Mit_MH(M+1000, kernel, mit1, GamMat);
        fprintf('MH acceptance rate: %4.2f (%s, %s). \n', accept(sim,P_bars==p_bar), model, algo);
        theta1 = theta1(1001:M+1000,:);

        %% High loss, 10 days horizon
        % approximate the high loss distribution of (theta,eps*) where eps*={eps_T+1,...,eps_T+hp}
        h_T = volatility_t_garch(theta1, data, S);
        [y_hp, eps_hp] = predict_t_garch(theta1, y_T, S, h_T, hp);

        % get the preliminary 10-day-ahead 99% VaR estimate as the 100th of the ascendingly sorted percentage loss values
        [PL_hp, ind] = sort(fn_PL(y_hp));

        VaR_prelim(sim,1) = PL_hp(p_bar*M);
        ES_prelim(sim,P_bars==p_bar) = mean(PL_hp(1:p_bar*M));   
        fprintf('Preliminary 100*%4.2f%% VaR estimate: %6.4f (%s, %s). \n', p_bar, VaR_prelim(sim,1), model, algo);
    end

    % take one value of VaR_prelim to construct mit2
    VaR_prelim_MC(:,P_bars==p_bar) = VaR_prelim;
    % VaR_prelim = VaR_prelim_MC(N_sim,1);       % the last one
    VaR_prelim = mean(VaR_prelim);              % the mean

    %% QERMit 1c.:
    % get mit approximation of the conditional joint density of
    % parameters and future returns given the returns are below VaR_prelim
    % approximation of the joint high loss distribution
    % here: not future returns but future disturbances  (varepsilons)

    %% High loss density approximation
    kernel_init = @(a) - posterior_t_garch_hl_mex(a, data, S, VaR_prelim, GamMat);
    kernel = @(a) posterior_t_garch_hl_mex(a, data, S, VaR_prelim, GamMat);

    % kernel_init = @(a) - posterior_t_garch_hl(a, data, S, VaR_prelim, L, hyper, GamMat);
    % kernel = @(a) posterior_t_garch_hl(a, data, S, VaR_prelim, L, hyper, GamMat);


    % Choose the starting point (mu_hl) for the constuction of the approximaton 
    % to the high loss (hl) region density
    theta_hl = theta1(ind,:);
    eps_hl = eps_hp(ind,:); 
    draw_hl = [theta1(ind,:), eps_hp(ind)];
    mu_init_hl = draw_hl(max(find(PL_hp < VaR_prelim)),:);    

    %% IS estimation of the initial mixture component 
    draw_hl =  draw_hl((find(PL_hp < VaR_prelim)),:);   
    lnk = kernel(draw_hl);
    ind = find(lnk~=-Inf);
    lnk = lnk(ind,:);
    draw_hl = draw_hl(ind,:);
    % lnd = dmvgt(theta1,mit_init,true);
    % w = fn_ISwgts(lnk, lnd, norm);
    w = lnk/sum(lnk);
    [mu_hl, Sigma_hl] = fn_muSigma(draw_hl, w);

    mit_hl.mu = mu_hl;
    mit_hl.Sigma = Sigma_hl;
    mit_hl.df = 5;
    mit_hl.p = 1;

    [mit2, summary2] = AdMit(mit_hl, kernel, mu_init_hl, cont2, GamMat);
    % [mit2_mex, summary2_mex] = MitISEM_new(mit_hl, kernel_mex, mu_init_hl, cont2, GamMat);
    % [mit2, summary] = MitISEM(kernel_init, kernel, mu_hl, cont, GamMat);


    %% QERMit 2:
    % use the mixture 0.5*mit1 + 0.5*mit2 as the importance density
    % to estiamte VaR and ES for theta and y (or alpha in eps)


    %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % MONTE CARLO VaR_IS and ES_IS (and their NSEs) ESTIMATION 
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    for sim = 1:N_sim
        resampl_on = false;
        fprintf('NSE sim = %i.\n', sim);
        kernel = @(a) posterior_t_garch_mex(a, data ,S, GamMat);
    %     kernel = @(a) posterior_t_garch(a, data, S, L, hyper, GamMat);
        [draw1, lnk1, ~] = fn_rmvgt_robust(M/2, mit1, kernel, resampl_on);
        eps1 = zeros(M/2, hp);
        for hh = 1:hp
           eps1(:,hh) = trnd(draw1(:,4)); % ERRORS ARE iid T!!
        end
        draw1_eps1 = [draw1(1:M/2,:), eps1];

        kernel = @(a) posterior_t_garch_hl_mex(a, data, S, VaR_prelim, GamMat);
    %     kernel = @(a) posterior_t_garch_hl(a, data, S, VaR_prelim, L, hyper, GamMat);
        [draw2, lnk2, ~] = fn_rmvgt_robust(M/2, mit2, kernel, resampl_on);
        % col 1-4 parameters, col 5:5+hp-1 eps

        draw_opt = [draw1_eps1; draw2];

        %% IS weights
    %     kernel = @(a) posterior_t_garch_whole(a, data, S, L, hyper, GamMat);
    %     lnk = kernel(draw_opt);

        kernel = @(a) posterior_t_garch_mex(a, data ,S, GamMat);
        lnk = kernel(draw_opt(:,1:4));
        eps_pdf = tpdf(draw_opt(:,5),draw_opt(:,4));
        lnk = lnk + log(eps_pdf);

    %     lnk = lnk1 + duvt(eps1, draw1(:,4), 1, true);
    %     lnk = [lnk; lnk2];

        % exp_lnd1 = 0.5*normpdf(draw_opt(:,2)).*dmvgt(draw_opt(:,1:4),mit1,false);
        % ep = duvt(draw_opt(:,5:5+hp-1), nu, hp, false);  % false: exp dnesity
        exp_lnd1 = 0.5*sum(duvt(draw_opt(:,5:5+hp-1), draw_opt(:,4), hp, false),2).*dmvgt(draw_opt(:,1:4), mit1, false, GamMat);
        exp_lnd2 = 0.5*dmvgt(draw_opt, mit2, false, GamMat);
        exp_lnd = exp_lnd1 + exp_lnd2;
        lnd = log(exp_lnd);

        w_opt = fn_ISwgts(lnk, lnd, false);

        %% VaR and ES IS estimates 
        h_T = volatility_t_garch(draw_opt(:,1:4), data, S);
        [y_opt, ~] = predict_t_garch(draw_opt(:,1:4), y_T, S, h_T, hp, draw_opt(:,5:5+hp-1));
        dens = struct('y',y_opt,'w',w_opt,'p_bar',p_bar);
        IS_estim = fn_PL(dens, 1);
        VaR_IS(sim,P_bars==p_bar) = IS_estim(1,1);
        ES_IS(sim,P_bars==p_bar) = IS_estim(1,2);

        if plot_on   
            PL_opt = fn_PL(y_opt);
            figure(8)
            set(gcf,'units','normalized','outerposition',[0 0 0.5 0.5]);
            set(gcf,'defaulttextinterpreter','latex');
            hold on
            plot(PL_opt_h1)
            pos = max(find(sort(PL_opt)<=VaR_IS(sim,1)));
            scatter(pos, VaR_IS(sim,1),'MarkerEdgeColor','red','MarkerFaceColor','red')
            pos = max(find(PL_opt_h1<=VaR_prelim));
            scatter(pos, VaR_prelim,'MarkerEdgeColor','green','MarkerFaceColor','green')      
            hold off
            title(['Sorted future profit/losses values $$PL(y_{T+1}^{(i)})$$. Model: ',model,'.'])
            set(gca,'TickLabelInterpreter','latex')

            if print_on
                name = 'figures/t_garch_predict.png';
                fig = gcf;
                fig.PaperPositionMode = 'auto';
                print(name,'-dpng','-r0')
            end
        end

        fprintf('IS 100*%4.2f%% VAR estimate: %6.4f (%s, %s). \n', p_bar, VaR_IS(sim,P_bars==p_bar), model, algo);
        fprintf('IS 100*%4.2f%% ES estimate: %6.4f (%s, %s). \n', p_bar, ES_IS(sim,P_bars==p_bar), model, algo);  
    end

    mean_VaR_prelim = mean(VaR_prelim_MC(:,P_bars==p_bar));
    mean_ES_prelim = mean(ES_prelim(:,P_bars==p_bar));

    NSE_VaR_prelim = std(VaR_prelim_MC(:,P_bars==p_bar));
    NSE_ES_prelim = std(ES_prelim(:,P_bars==p_bar));
    
    mean_VaR_IS = mean(VaR_IS(:,P_bars==p_bar));
    mean_ES_IS = mean(ES_IS(:,P_bars==p_bar));

    NSE_VaR_IS = std(VaR_IS(:,P_bars==p_bar));
    NSE_ES_IS = std(ES_IS(:,P_bars==p_bar));

    fprintf('100*%4.2f%% VaR prelim (mean) estimate: %6.4f (%s, %s). \n', p_bar, mean_VaR_prelim, model, algo);
    fprintf('NSE VaR prelim: %6.4f (%s, %s). \n', NSE_VaR_prelim, model, algo);
    fprintf('VaR prelim: [%6.4f, %6.4f] (%s, %s). \n \n', mean_VaR_prelim - NSE_VaR_prelim, mean_VaR_prelim + NSE_VaR_prelim, model, algo);

    fprintf('100*%4.2f%% VaR IS (mean) estimate: %6.4f (%s, %s). \n',  p_bar, mean_VaR_IS, model, algo);
    fprintf('NSE VaR IS estimate: %6.4f (%s, %s). \n', NSE_VaR_IS, model, algo);
    fprintf('VaR: [%6.4f, %6.4f] (%s, %s). \n \n', mean_VaR_IS - NSE_VaR_IS, mean_VaR_IS + NSE_VaR_IS, model, algo);

    fprintf('100*%4.2f%% ES prelim (mean) estimate: %6.4f (%s, %s). \n', p_bar, mean_ES_prelim, model, algo);
    fprintf('NSE ES prelim: %6.4f (%s, %s). \n',NSE_ES_prelim, model, algo);
    fprintf('ES prelim: [%6.4f, %6.4f] (%s, %s). \n \n', mean_ES_prelim - NSE_ES_prelim, mean_ES_prelim + NSE_ES_prelim, model, algo);

    fprintf('100*%4.2f%% ES IS (mean) estimate: %6.4f (%s, %s). \n', p_bar, mean_ES_IS, model, algo);
    fprintf('NSE ES IS estimate: %6.4f (%s, %s). \n', NSE_ES_IS, model, algo);
    fprintf('ES: [%6.4f, %6.4f] (%s, %s). \n',  mean_ES_IS - NSE_ES_IS, mean_ES_IS + NSE_ES_IS, model, algo);
     
    
    if plot_on2
        figure(390+100*p_bar)
%         set(gcf, 'visible', 'off');
%         set(gcf,'defaulttextinterpreter','latex');
        boxplot([VaR_prelim_MC(:,P_bars==p_bar), VaR_IS(:,P_bars==p_bar)],'labels',{'VaR_prelim MC','VaR_IS'})        
        title(['100*', num2str(p_bar),'% VaR estimates: prelim and IS (',model,', ',algo,', M = ',num2str(M),', N\_sim = ', num2str(N_sim),').'])
        if v_new
            set(gca,'TickLabelInterpreter','latex')
        else
            plotTickLatex2D;
        end
        if print_on
            name = ['figures/(',model,'_',algo,')', num2str(p_bar),'_VaR_box_',num2str(M),'.png'];
            fig = gcf;
            fig.PaperPositionMode = 'auto';
            print(name,'-dpng','-r0')
        end
    
        %%%%%%%%%%%%%%%%%%%%%%%%
        
        figure(3900+100*p_bar)
%         set(gcf, 'visible', 'off');
%         set(gcf,'defaulttextinterpreter','latex');
        hold on; 
        bar(VaR_IS(:,P_bars==p_bar),'FaceColor',[0 0.4470 0.7410], 'EdgeColor','w'); 
        plot(0:(N_sim+1), (mean_VaR_prelim - NSE_VaR_prelim)*ones(N_sim+2,1),'r--'); 
        plot(0:(N_sim+1), (mean_VaR_prelim + NSE_VaR_prelim)*ones(N_sim+2,1),'r--'); 
        plot(0:(N_sim+1), mean_VaR_prelim*ones(N_sim+2,1),'r'); 
        hold off;
        title(['100*', num2str(p_bar),'% VaR IS estimates and the mean VaR prelim (+/- NSE VaR prelim) (',model,', ',algo,', M = ',num2str(M),', N\_sim = ', num2str(N_sim),').'])    
    
        if v_new
            set(gca,'TickLabelInterpreter','latex')
        else
            plotTickLatex2D;
        end
        if print_on
            name = ['figures/(',model,'_',algo,')', num2str(p_bar),'_VaR_bar_',num2str(M),'.png'];
            fig = gcf;
            fig.PaperPositionMode = 'auto';
            print(name,'-dpng','-r0')
        end
    end
    if save_on
        gen_out2;
    end
end

% if save_on
%     cont = cont2;
%     
%     s='mitisem';
%     gen_out
%         
%     clear GamMat x fig
%     save(['results/t_garch_mitisem_',num2str(hp),'.mat']);
% end