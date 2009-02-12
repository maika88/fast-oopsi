% this script generates a simulation of a movie containing a single cell
% using the following generative model:
%
% F_t = \sum_i a_i*C_{i,t} + b + sig*eps_t, eps_t ~ N(0,I)
% C_{i,t} = gam*C_{i,t-1} + n_{i,t},      n_{i,t} ~ Poisson(lam_i*dt)
%
% where ai,b,I are p-by-q matrices.
% we let b=0 and ai be the difference of gaussians (yielding a zero mean
% matrix)
%

clear, clc

% 1) generate spatial filters

% stuff required for each spatial filter
Nc      = 1;                                % # of cells in the ROI
neur_w  = 13;                               % width per neuron
width   = 20;                               % width of frame (pixels)
height  = Nc*neur_w;                        % height of frame (pixels)
Npixs   = width*height;                     % # pixels in ROI
x1      = linspace(-5,5,height);
x2      = linspace(-5,5,width);
[X1,X2] = meshgrid(x1,x2);
g1      = zeros(Npixs,Nc);
g2      = 0*g1;
Sigma1  = diag([1,1])*1;                    % var of positive gaussian
Sigma2  = diag([1,1])*2;                    % var of negative gaussian
mu      = [1 1]'*linspace(-2,2,Nc);         % means of gaussians for each cell (distributed across pixel space)
w       = Nc:-1:1;                          % weights of each filter

% spatial filter
for i=1:Nc
    g1(:,i)  = w(i)*mvnpdf([X1(:) X2(:)],mu(:,i)',Sigma1);
    g2(:,i)  = w(i)*mvnpdf([X1(:) X2(:)],mu(:,i)',Sigma2);
end
a_b = sum(g1-g2,2);

% 2) set simulation metadata
Sim.T       = 500;                              % # of time steps
Sim.dt      = 0.005;                            % time step size
Sim.MaxIter = 0;                                % # iterations of EM to estimate params
Sim.Np      = Npixs;                            % # of pixels in each image
Sim.w       = width;                            % width of frame (pixels)
Sim.h       = height;                           % height of frame (pixels)
Sim.Nc      = Nc;                               % # cells
Sim.plot    = 0;                                % whether to plot filter with each iteration

% 3) initialize params
P.a     = 0*g1;
for i=1:Sim.Nc
    P.a(:,i)=g1(:,i)-g2(:,i);
end
P.b     = 0*P.a(:,1)+1;                           % baseline is zero

P.sig   = 0.05;                                 % stan dev of noise (indep for each pixel)
C_0     = 0;                                    % initial calcium
tau     = round(100*rand(Sim.Nc,1))/100+0.05;   % decay time constant for each cell
P.gam   = 1-Sim.dt./tau(1:Sim.Nc);
P.lam   = round(10*rand(Sim.Nc,1))+5;           % rate-ish, ie, lam*dt=# spikes per second

% 3) simulate data
n=zeros(Sim.T,Sim.Nc);
C=n;
for i=1:Sim.Nc
    n(1,i)      = C_0;
    n(2:end,i)  = poissrnd(P.lam(i)*Sim.dt*ones(Sim.T-1,1));    % simulate spike train
    C(:,i)      = filter(1,[1 -P.gam(i)],n(:,i));               % calcium concentration
end
Z = 0*n(:,1);
F = C*P.a' + (1+Z)*P.b'+P.sig*randn(Sim.T,Npixs);               % fluorescence


%% 4) other stuff
MakMov  = 1;
% make movie of raw data
if MakMov==1
    for i=1:Sim.T
        if i==1, mod='overwrite'; else mod='append'; end
        imwrite(reshape(F(i,:),width,height),'Multi_Mov.tif','tif','Compression','none','WriteMode',mod)
    end
end

GetROI  = 0;
fnum    = 0;

if GetROI
    figure(100); clf,imagesc(reshape(sum(g1-g2,2),width,height))
    for i=1:Nc
        [x y]   = ginput(4);
        ROWS    = [round(mean(y(1:2))) round(mean(y(3:4)))];                              % define ROI
        COLS    = [round(mean(x([1 4]))) round(mean(x(2:3)))];
        COLS1{i}=COLS;
        ROWS1{i}=ROWS;
        save('ROIs','ROWS1','COLS1')
    end
else
    load ROIs
end


%% end-1) infer spike train using various approaches
qs=1:6;%[1 2 3];
MaxIter=10;
for q=qs
    GG=F; Tim=Sim;
    %     if q==1,                        % estimate spatial filter from real spikes
    %         SpikeFilters;
    %     elseif q==3                     % denoising using SVD of an ROI around each cell, and using first SVD's as filters
    %         ROI_SVD_Filters;
    %     elseif q==4                     % denoising using mean of an ROI around each cell
    %         ROI_mean_Filters;
    %     elseif q==6                     % infer spikes from d-r'ed data
    %         d_r_smoother_Filter;
    if q==1,
        Phat{q}=P;
        I{q}.label='True Filter';
    elseif q==2,
        SVDFilters;
    elseif q==3,
        SVD_no_mean_Filters;
    elseif q==4;
        Tim.MaxIter=MaxIter;
        SVDFilters;
        I{q}.label='SVD init, est Filter';
    elseif q==5;
        Tim.MaxIter=MaxIter;
        SVDFilters;
        GG=Denoised;
        I{q}.label='SVD denoise, SVD init, est Filter';        
    elseif q==6;
        Tim.MaxIter=MaxIter;
        SVD_no_mean_Filters;
        GG=Denoised;
        I{q}.label='SVD no mean denoise, SVD init, est Filter';        
    end
    display(I{q}.label)
    [I{q}.n I{q}.P] = FOOPSI2_59(GG,Phat{q},Tim);
end

%% end) plot results
clear Pl
nrows   = 2+Nc;                                  % set number of rows
h       = zeros(nrows,1);
Pl.xlims= [5 Sim.T];                            % time steps to plot
Pl.nticks=5;                                    % number of ticks along x-axis
Pl.n    = double(n); Pl.n(Pl.n==0)=NaN;         % store spike train for plotting
Pl      = PlotParams(Pl);                       % generate a number of other parameters for plotting
Pl.vs   = 2;
Pl.colors(1,:) = [0 0 0];
Pl.colors(2,:) = Pl.gray;
Pl.colors(3,:) = [.5 0 0];
Pl.Nc   = Sim.Nc;

for q=qs
    fnum = figure(fnum+1); clf,

    % plot fluorescence data
    i=1; h(i) = subplot(nrows,1,i);
    Pl.label = [{'Spatially'}; {'Filtered'}; {'Fluorescence'}];
    Pl.color = 'k';
    Plot_nX(Pl,F*Phat{q}.a);
    title(I{q}.label)

    % plot calcium
    i=i+1; h(i) = subplot(nrows,1,i);
    Pl.label = 'Calcium';
    Pl.color = Pl.gray;
    Plot_nX(Pl,C);

    % plot inferred spike trains
    Pl.label = [{'Spike'}; {'Train'}];
    for j=1:Nc
        i=i+1; h(i) = subplot(nrows,1,i);
        Pl.j=j;
        Plot_n_MAPs(Pl,I{q}.n(:,j));
    end

    % set xlabel stuff
    subplot(nrows,1,nrows)
    set(gca,'XTick',Pl.XTicks,'XTickLabel',Pl.XTicks*Sim.dt,'FontSize',Pl.fs)
    xlabel('Time (sec)','FontSize',Pl.fs)
    linkaxes(h,'x')

    % print fig
    wh=[7 5];   %width and height
    set(fnum,'PaperPosition',[0 11-wh(2) wh]);
    print('-depsc',['Multi_Spikes' num2str(q)])
end


% plot true filters, svd's, and estimated filters
fnum=fnum+1; figure(fnum), clf, 
mn(1) = min([min(P.a) min(P.b)]);
mx(1) = (max([max(P.a) max(P.b)])-mn(1))/60;

mx(2) = (max(Phat{q}.a(:))-mn(1))/60;
mn(2) = min(Phat{q}.a(:));

for q=qs(qs>3)
    mn(q) = min([min(I{q}.P.a(:)) min(I{q}.P.b)]);
    mx(q) = (max([max(I{q}.P.a(:)) max(I{q}.P.b)])-mn(q))/60;
end

%     mx = (max([max(P.a) max(Phat{q}.a) max(I{q}.P.a) max(I{q}.P.b) max(P.b)])-mn)/60;
nrows=1+Nc;
ncols=1+numel(qs(qs>3));
for i=1:Nc, % true filters
    subplot(ncols,nrows,i),
    image(reshape((P.a(:,i)-mn(1))/mx(1),Sim.w,Sim.h)),
end
subplot(ncols,nrows,nrows), image(reshape((P.b-mn(1))/mx(1),Sim.w,Sim.h))

if any(qs==2)  % svd's
    for i=1:Nc, subplot(ncols,nrows,i+nrows),
        image(reshape((Phat{2}.a(:,i)-mn(2))/mx(2),Sim.w,Sim.h)),
    end
    subplot(ncols,nrows,2*nrows), image(reshape((Phat{2}.b-mn(2))/mx(2),Sim.w,Sim.h))
end

for q=qs(qs>3) % estimated filters
    for i=1:Nc, 
        subplot(ncols,nrows,i+(q-3)*nrows),
        image(reshape((I{q}.P.a(:,i)-mn(q))/mx(q),Sim.w,Sim.h)),
    end
    subplot(ncols,nrows,(q-2)*nrows), image(reshape((I{q}.P.b-mn(q))/mx(q),Sim.w,Sim.h))
end

% print fig
wh=[7 5];   %width and height
set(fnum,'PaperPosition',[0 11-wh(2) wh]);
print('-depsc','Auto_Filters')

% plot iterative lik
for q=qs(qs>3)
    fnum=fnum+1; figure(fnum), clf
    subplot(211), plot(I{q}.P.l), axis('tight')
    subplot(212), plot(diff(I{q}.P.l)), hold on, plot(0*diff(I{q}.P.l),'k'), hold off, axis('tight')
    % print fig
    wh=[7 5];   %width and height
    set(fnum,'PaperPosition',[0 11-wh(2) wh]);
    print('-depsc',['lik' num2str(q)])
end

%%
fnum=fnum+1; figure(fnum), clf
subplot(1,Nc+1,1), imagesc(reshape(sum(P.a,2),Sim.w,Sim.h))
title('sum of filters')
for i=1:Nc
    subplot(1,Nc+1,1+i), imagesc(reshape(P.a(:,i),Sim.w,Sim.h))
    title(['filter ' num2str(i)])
end
wh=[7 3];   %width and height
set(fnum,'PaperPosition',[0 11-wh(2) wh]);
print('-depsc','filters')

% fnum=fnum+1;
% fig=figure(fnum); imagesc(F')
% set(fig,'PaperPosition',[0 11-wh(2) wh]);
% print('-deps','RAW_2D')
%
% fnum=fnum+1;
% fig=figure(fnum); imagesc(Denoised')
% set(fig,'PaperPosition',[0 11-wh(2) wh]);
% print('-deps','SVD_2D')
%
% %%
% pixel=min(656,Sim.Np);
% fig=figure(fig+1); plot(F(:,pixel))
% set(fig,'PaperPosition',[0 11-wh(2) wh]);
% print('-deps','RAW_1D')
%
% fig=figure(fig+2); plot(Denoised(:,pixel))
% set(fig,'PaperPosition',[0 11-wh(2) wh]);
% print('-deps','SVD_1D')