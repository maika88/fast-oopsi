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

% % stuff required for each spatial filter
Nc      = 1;                                % # of cells in the ROI
neur_w  = 1;                               % width per neuron
width   = 1;                               % width of frame (pixels)
height  = Nc*neur_w;                        % height of frame (pixels)
Npixs   = width*height;                     % # pixels in ROI
% x1      = linspace(-5,5,height);
% x2      = linspace(-5,5,width);
% [X1,X2] = meshgrid(x1,x2);
% g1      = zeros(Npixs,Nc);
% g2      = 0*g1;
% Sigma1  = diag([1,1])*1;                    % var of positive gaussian
% Sigma2  = diag([1,1])*2;                    % var of negative gaussian
% mu      = [1 1]'*linspace(-2,2,Nc);         % means of gaussians for each cell (distributed across pixel space)
% w       = Nc:-1:1;                          % weights of each filter
%
% % spatial filter
% for i=1:Nc
%     g1(:,i)  = w(i)*mvnpdf([X1(:) X2(:)],mu(:,i)',Sigma1);
%     g2(:,i)  = w(i)*mvnpdf([X1(:) X2(:)],mu(:,i)',Sigma2);
% end
% a_b = sum(g1-g2,2);

% 2) set simulation metadata
Sim.T       = 500;                              % # of time steps
Sim.dt      = 0.005;                            % time step size
Sim.MaxIter = 0;                                % # iterations of EM to estimate params
Sim.Np      = Npixs;                            % # of pixels in each image
Sim.w       = width;                            % width of frame (pixels)
Sim.h       = height;                           % height of frame (pixels)
Sim.Nc      = Nc;                               % # cells
Sim.plot    = 0;                                % whether to plot filter with each iteration

lam         = [10; 500];
sigs        = [1/4 8];
moda        = (sin(linspace(0,10*pi,Sim.T-1))+1)/2;
qs          = 1:2;

for q=qs
    % 3) initialize params
    P.a     = 1;
    % for i=1:Sim.Nc
    %     P.a(:,i)=g1(:,i)-g2(:,i);
    % end
    P.b     = 0;                           % baseline is zero
    % P.b     = 0*P.a(:,1)+1;                           % baseline is zero

    P.sig   = sigs(q);                                 % stan dev of noise (indep for each pixel)
    C_0     = 0;                                    % initial calcium
    tau     = [.1 .5]; %round(100*rand(Sim.Nc,1))/100+0.05;   % decay time constant for each cell
    P.gam   = 1-Sim.dt./tau(1:Sim.Nc);
    P.lam   = lam(q);%round(10*rand(Sim.Nc,1))+5;           % rate-ish, ie, lam*dt=# spikes per second

    % 3) simulate data
    n=zeros(Sim.T,Sim.Nc);
    C=n;
    for i=1:Sim.Nc
        n(1,i)      = C_0;
        n(2:end,i)  = poissrnd(P.lam(i)*Sim.dt*moda);    % simulate spike train
        C(:,i)      = filter(1,[1 -P.gam(i)],n(:,i));               % calcium concentration
    end
    Z = 0*n(:,1);
    F = C*P.a' + (1+Z)*P.b'+P.sig*randn(Sim.T,Npixs);               % fluorescence

    D{q}.n=n; D{q}.C=C; D{q}.F=F;

    %% 4) other stuff
    MakMov  = 0;
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


    GG=D{q}.F; Tim=Sim;
    Phat{q}=P;
    I{q}.label='True Filter';
    display(I{q}.label)
    [I{q}.n I{q}.P] = FOOPSI2_59(GG,Phat{q},Tim);
    [I{q+numel(qs)}.n I{q+numel(qs)}.P]   = WienerFilt1_2(F,Sim.dt,P);
end

%% end) plot results
clear Pl
nrows   = 2+Nc;                                  % set number of rows
ncols   = 2;
h       = zeros(nrows,1);
Pl.xlims= [5 Sim.T-101];                            % time steps to plot
Pl.nticks=5;                                    % number of ticks along x-axis
Pl.n    = double(n); Pl.n(Pl.n==0)=NaN;         % store spike train for plotting
Pl      = PlotParams(Pl);                       % generate a number of other parameters for plotting
Pl.vs   = 2;
Pl.colors(1,:) = [0 0 0];
Pl.colors(2,:) = Pl.gray;
Pl.colors(3,:) = [.5 0 0];
Pl.Nc   = Sim.Nc;
fnum = figure(1); clf,

for q=qs
    Pl.n    = double(D{q}.n); Pl.n(Pl.n==0)=NaN;         % store spike train for plotting

    % plot fluorescence data
    i=q; h(i) = subplot(nrows,ncols,i);
    if q==1, 
        Pl.label = [{'Fluorescence'}];
        title('Slow Firing Rate')
    else
        Pl.label = [];
        title('Fast Firing Rate')
    end
    Pl.color = 'k';
    Plot_nX(Pl,D{q}.F*Phat{q}.a);
    %     title(I{q}.label)

    % plot fast spike trains
    i=i+2; h(i) = subplot(nrows,ncols,i);
    if q==1,
        Pl.label = [{'Fast'}; {'Filter'}];
        Pl.j=1;
        Plot_n_MAPs(Pl,I{q}.n);
    else
        Pl.label = [];
        hold on
        a=75; 
        gaus = exp(-(-Sim.T/2:Sim.T/2).^2);
        ass=conv(exp(-(linspace(-a,a,Sim.T)).^2),I{q}.n);
        plot(ass(Sim.T/2+(Pl.xlims(1):Pl.xlims(2))),'Color','k','LineWidth',Pl.lw);
        ass=conv(exp(-(linspace(-a,a,Sim.T)).^2),D{q}.n);
        plot(ass(Sim.T/2+(Pl.xlims(1):Pl.xlims(2))),'Color',Pl.gray,'LineWidth',1);   
        ylab=ylabel(Pl.label,'Interpreter',Pl.inter,'FontSize',Pl.fs);
        set(ylab,'Rotation',0,'HorizontalAlignment','right','verticalalignment','middle')
        set(gca,'YTick',[],'YTickLabel',[])
        set(gca,'XTick',Pl.XTicks,'XTickLabel',[],'FontSize',Pl.fs)
        X=[I{q}.n D{q}.n];
        axis([Pl.xlims-Pl.xlims(1) min(X(:)) max(ass(:))])
        box off
    end

% set ylabel stuff
    if q==1
        Pl.YTicks=0:max(D{q}.n):max(D{q}.n);
    else
        Pl.YTicks=0:round(max(ass)/2):round(max(ass));
    end
    Pl.YTickLabels=Pl.YTicks;
    set(gca,'YTick',Pl.YTicks,'YTickLabel',Pl.YTicks, 'FontSize',10)

    % plot wiener spike trains
    i=i+2; h(i) = subplot(nrows,ncols,i);
    if q==1,
        Pl.label = [{'Wiener'}; {'Filter'}];
        Pl.j=1;
        Plot_n_MAPs(Pl,I{q+2}.n);
    else
        Pl.label = [];
        hold on
        a=75; 
        gaus = exp(-(-Sim.T/2:Sim.T/2).^2);
        ass=conv(exp(-(linspace(-a,a,Sim.T)).^2),I{q}.n);
        plot(ass(Sim.T/2+(Pl.xlims(1):Pl.xlims(2))),'Color','k','LineWidth',Pl.lw);
        ass=conv(exp(-(linspace(-a,a,Sim.T)).^2),D{q}.n);
        plot(ass(Sim.T/2+(Pl.xlims(1):Pl.xlims(2))),'Color',Pl.gray,'LineWidth',1);   
        ylab=ylabel(Pl.label,'Interpreter',Pl.inter,'FontSize',Pl.fs);
        set(ylab,'Rotation',0,'HorizontalAlignment','right','verticalalignment','middle')
        set(gca,'YTick',[],'YTickLabel',[])
        set(gca,'XTick',Pl.XTicks,'XTickLabel',[],'FontSize',Pl.fs)
        X=[I{q}.n D{q}.n];
        axis([Pl.xlims-Pl.xlims(1) min(X(:)) max(ass(:))])
        box off
    end

    % set ylabel stuff
    if q==1
        Pl.YTicks=0:max(D{q}.n):max(D{q}.n);
    else
        Pl.YTicks=0:round(max(ass)/2):round(max(ass));
    end
    Pl.YTickLabels=Pl.YTicks;
    set(gca,'YTick',Pl.YTicks,'YTickLabel',Pl.YTicks, 'FontSize',10)

    subplot(nrows,ncols,i)
    set(gca,'XTick',Pl.XTicks,'XTickLabel',Pl.XTicks*Sim.dt,'FontSize',Pl.fs)
    xlabel('Time (sec)','FontSize',Pl.fs)
    %     linkaxes(h,'x')

    % print fig
    wh=[7 5];   %width and height
    set(fnum,'PaperPosition',[0 11-wh(2) wh]);
    print('-depsc','wiener')
end