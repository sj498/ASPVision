function [net, info] = cnn_cifar_ASP(varargin)
% CNN_CIFAR   Demonstrates MatConvNet on CIFAR-10
% Edits by Suren Jayasuriya to add AlexNet training, and option to train on
% ASP data
%    The demo includes two standard model: LeNet and Network in
%    Network (NIN). Use the 'modelType' option to choose one.

run(fullfile(fileparts(mfilename('fullpath')), ...
  '..', 'matlab', 'vl_setupnn.m')) ;
addpath(‘..’)
opts.modelType = 'nin-ASP' ;
[opts, varargin] = vl_argparse(opts, varargin) ;

switch opts.modelType
  case 'lenet'
    opts.train.learningRate = [0.05*ones(1,15) 0.005*ones(1,10) 0.0005*ones(1,5)] ;
    opts.train.weightDecay = 0.0001 ;
  case 'nin-ASP'
       opts.train.learningRate = [0.5*ones(1,30) 0.1*ones(1,10) 0.02*ones(1,10)] ;
    opts.train.weightDecay = 0.0005 ;
%     opts.train.learningRate = [0.5*ones(1,30) 0.1*ones(1,10) 0.02*ones(1,10)  0.01*ones(1,10) 0.005*ones(1,10)] ; %[0.5,(30), 0.1*(10), 0.02*(10)]
%     opts.train.weightDecay = 0.0005 ; %0.0005
  case 'vvg-f'
    opts.train.learningRate = 0.*[0.5*ones(1,30) 0.1*ones(1,10) 0.02*ones(1,10)] ; %[0.5, 0.1, 0.02]
    opts.train.weightDecay = 0.0005 ; %0.0005 
  otherwise
    error('Unknown model type %s', opts.modelType) ;
end
opts.expDir = fullfile('data', sprintf('cifar-asp-3x3--%s', opts.modelType)) ;
[opts, varargin] = vl_argparse(opts, varargin) ;

opts.train.numEpochs = numel(opts.train.learningRate) ;
[opts, varargin] = vl_argparse(opts, varargin) ;

opts.dataDir = fullfile('data','cifar') ;
opts.imdbPath = fullfile(opts.expDir, 'imdb.mat');
opts.whitenData = false ;
opts.contrastNormalization = false;
opts.train.batchSize = 100 ;
opts.train.continue = true ;
opts.train.gpus = 1 ;
opts.train.expDir = opts.expDir ;
opts = vl_argparse(opts, varargin) ;

% --------------------------------------------------------------------
%                                               Prepare data and model
% --------------------------------------------------------------------

switch opts.modelType
  case 'lenet', net = cnn_cifar_init(opts) ;
  case 'nin',   net = cnn_cifar_init_nin(opts) ;
  case 'nin-ASP', net = ASP_cnn_cifar_init_nin(opts);
  case 'vvg-f',  urlwrite('http://www.vlfeat.org/sandbox-matconvnet/models/imagenet-vgg-f.mat', ...
          'imagenet-vgg-f.mat') ; net = load('imagenet-vgg-f.mat') ;
end

if exist(opts.imdbPath, 'file')
  imdb = load(opts.imdbPath) ;
else
  imdb = getCifarImdb(opts) ;
  mkdir(opts.expDir) ;
%   save(opts.imdbPath, '-struct', 'imdb') ; %edit saving to avoid crash
end

% --------------------------------------------------------------------
%                                                                Train
% --------------------------------------------------------------------

[net, info] = cnn_train(net, imdb, @getBatch, ...
    opts.train, ...
    'val', find(imdb.images.set == 3)) ;

% --------------------------------------------------------------------
function [im, labels] = getBatch(imdb, batch)
% --------------------------------------------------------------------
im = imdb.images.data(:,:,:,batch) ;
labels = imdb.images.labels(1,batch) ;
if rand > 0.5, im=fliplr(im) ; end

% --------------------------------------------------------------------
function imdb = getCifarImdb(opts)
% --------------------------------------------------------------------
% Preapre the imdb structure, returns image data with mean image subtracted
unpackPath = fullfile(opts.dataDir, 'cifar-10-batches-mat');
files = [arrayfun(@(n) sprintf('data_batch_%d.mat', n), 1:5, 'UniformOutput', false) ...
  {'test_batch.mat'}];
files = cellfun(@(fn) fullfile(unpackPath, fn), files, 'UniformOutput', false);
file_set = uint8([ones(1, 5), 3]);

if any(cellfun(@(fn) ~exist(fn, 'file'), files))
  url = 'http://www.cs.toronto.edu/~kriz/cifar-10-matlab.tar.gz' ;
  fprintf('downloading %s\n', url) ;
  untar(url, opts.dataDir) ;
end

data = cell(1, numel(files));
labels = cell(1, numel(files));
sets = cell(1, numel(files));
for fi = 1:numel(files)
  fd = load(files{fi}) ;
  data{fi} = permute(reshape(fd.data',32,32,3,[]),[2 1 3 4]) ;
  labels{fi} = fd.labels' + 1; % Index from 1
  sets{fi} = repmat(file_set(fi), size(labels{fi}));
end

set = cat(2, sets{:});
data = single(cat(4, data{:}));

%  % Suren black/white data processing
% data = mean(data,3);
% data = data(:,:,1,:);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% process data [32 32 3 60000] --> ASP data [32 32 25 60000]
%load parameters
loadASPparam;

%Tile pattern
% nfSort1=[47 35  5 43 13 19 ...
%           7 45  1 29 39 27 ...
%          31 17  9 21 15 33 ...
%          37 41 25  3 23 11];
% nfSort2= nfSort1 + 1;

% no sin/cosine distinction
nfSort1=[47 35  5 43 13 19 ...
          1 29 39 27 ...
           9 21];
nfSort2= nfSort1 + 1;


% Construct ASP transform matrix, stored in ASP variable. GW_sj = makes
% gabor wavelet corresponding to each type of ASP 

M = 3;   % n samples in response (long axis)
A = 0.7; % peak amplitude of response
S = 2;   % Scale of gaussian window
I0 = 0.3; % base intensity scale


for zz=1:12
    lamb = nfSort1(zz);
    lamb2 = nfSort2(zz);
    temp = Gw(I0,M,A,par(lamb,:));   
    temp2 = Gw(I0,M,A,par(lamb2,:));
    ASP{zz} = temp-temp2;
    ASP{zz} = fliplr(ASP{zz});
    ASPtemp = ASP{zz};
    ASP{zz} = (ASPtemp-min(ASPtemp(:)))./(max(ASPtemp(:))-min(ASPtemp(:))); %add normalization
    ASP{zz} = ASP{zz} .* 2 - 1;
%     figure, imagesc(ASP{zz}); colormap gray;
end
% temp = Amp(M,S);
% ASP{25} = temp;
% ASP{25} = (temp-min(temp(:)))./(max(temp(:))-min(temp(:)));

wscale = 1;


for zz=1:12
    for c=1:3
        wASP(:,:,c,zz) = wscale.*ASP{zz};
    end
end


%%%%% Insert additional features here %%%%%%%%%%%%%%%%%%%





%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

wASP = single(wASP);


% Perform ASP convolutions
data = vl_nnconv(data,wASP,[],'Pad',1);
data = (data-min(data(:)))./(max(data(:))-min(data(:))).*255;
data = single(data);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % % DIMENSIONALITY CHECK
% for c=4:25
% data(:,:,c,:) = squeeze(randn(32,32,size(data,4)));
% end

% remove mean in any case
dataMean = mean(data(:,:,:,set == 1), 4);
data = bsxfun(@minus, data, dataMean);

% normalize by image mean and std as suggested in `An Analysis of
% Single-Layer Networks in Unsupervised Feature Learning` Adam
% Coates, Honglak Lee, Andrew Y. Ng

if opts.contrastNormalization
  z = reshape(data,[],60000) ;
  z = bsxfun(@minus, z, mean(z,1)) ;
  n = std(z,0,1) ;
  z = bsxfun(@times, z, mean(n) ./ max(n, 40)) ;
  data = reshape(z, 32, 32, 3, []) ;
end

if opts.whitenData
  z = reshape(data,[],60000) ;
  W = z(:,set == 1)*z(:,set == 1)'/60000 ;
  [V,D] = eig(W) ;
  % the scale is selected to approximately preserve the norm of W
  d2 = diag(D) ;
  en = sqrt(mean(d2)) ;
  z = V*diag(en./max(sqrt(d2), 10))*V'*z ;
  data = reshape(z, 32, 32, 3, []) ;
end


clNames = load(fullfile(unpackPath, 'batches.meta.mat'));

imdb.images.data = data ;
imdb.images.labels = single(cat(2, labels{:})) ;
imdb.images.set = set;
imdb.meta.sets = {'train', 'val', 'test'} ;
imdb.meta.classes = clNames.label_names;
