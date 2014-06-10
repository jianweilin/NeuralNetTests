clear all; close all; clc; 
addpath('./Utils');
% addpath('./Liblinear');

addpath('./liblinear-1.94/matlab');
TrnSize = 600; 
ImgSize = 28; 
ImgFormat = 'gray'; %'color' or 'gray'

%% Loading data from MNIST Basic (10000 training, 2000 validation, 50000 testing) 
% load mnist_basic data
% load('./MNISTdata/mnist_basic'); 
load('trainLabelsK.mat');
load('trainDataK.mat');
load('testDataK.mat');

% ===== Reshuffle the training data =====
% Randnidx = randperm(size(mnist_train,1)); 
% mnist_train = mnist_train(Randnidx,:); 
% =======================================

% TrnData = mnist_train(1:TrnSize,1:end-1)';  % partition the data into training set and validation set
% TrnLabels = mnist_train(1:TrnSize,end);
% ValData = mnist_train(TrnSize+1:end,1:end-1)';
% ValLabels = mnist_train(TrnSize+1:end,end);

TrnData = trainData(1:TrnSize, 1:end)';
TrnLabels = trainLabels(1:TrnSize,end);
% ValData = trainData(TrnSize+1:TrnSize+2000,1:end)';
% ValLabel = trainLabels(TrnSize+1:TrnSize+2000, end);




% TestData = mnist_test(:,1:end-1)';
% TestLabels = mnist_test(:,end);

% TestData = mnistData(TrnSize+1:end,1:end)';
% TestLabels = mnistLabels(TrnSize+1:end, end);

%% test using subset of trainset 

% TestData = trainData(TrnSize+1:end,1:end)';
% TestLabels = trainLabels(TrnSize+1:end, end);

%% for test dataset
TestData = mnistTestData(1:end,1:end)';

testsize = size(TestData);
testlabel = testsize(2);
TestLabels = zeros(testlabel,1);


clear trainData;
clear mnist_train;
clear mnist_test;
clear ans;
clear mnistData;
clear mnistLabels;


%% ==== Subsampling the Training and Testing sets ============
%(comment out the following four lines for a complete test) 
TrnData = TrnData(:,1:4:end);  % sample around 2500 training samples
TrnLabels = TrnLabels(1:4:end); % 

TestData = TestData(:,1:50:end);  % sample around 1000 test samples  
TestLabels = TestLabels(1:50:end); 

%% ===========================================================

nTestImg = length(TestLabels);

%% PCANet parameters 
PCANet.NumStages = 2;
PCANet.PatchSize = 7;
PCANet.NumFilters = [8 8];
PCANet.HistBlockSize = [7 7]; 
PCANet.BlkOverLapRatio = 0.5;

fprintf('\n ====== PCANet Parameters ======= \n')
PCANet

%% PCANet Training with 10000 samples

fprintf('\n ====== PCANet Training ======= \n')
TrnData_ImgCell = mat2imgcell(TrnData,ImgSize,ImgSize,ImgFormat); % convert columns in TrnData to cells 
clear TrnData; 
tic;
[ftrain V BlkIdx] = PCANet_train(TrnData_ImgCell,PCANet,1); % BlkIdx serves the purpose of learning block-wise DR projection matrix; e.g., WPCA
PCANet_TrnTime = toc;
clear TrnData_ImgCell; 


%% cv
fprintf(1,'step3: Cross Validation for choosing parameter c...\n');
% the larger c is, more time should be costed
c = [2^-6 2^-5 2^-4 2^-3 2^-2 2^-1 2^0 2^1 2^2 2^3];
max_acc = 0;
tic;
for i = 1 : size(c, 2)
	option = ['-B 1 -c ' num2str(c(i)) ' -v 5 -q -s 0'];
	fprintf(1,'Stage: %d/%d: c = %d, ', i, size(c, 2), c(i));
	accuracy =  train(TrnLabels, ftrain',  option);
	if accuracy > max_acc
		max_acc = accuracy;
		best_c = i;
	end
end
fprintf(1,'The best c is c = %d.\n', c(best_c));
toc;


%% train
fprintf('\n ====== Training Linear SVM Classifier ======= \n')
tic;
option = ['-c' num2str(c(best_c))  '-s 1 -q'];
%models = train(TrnLabels, ftrain', '-c 0.5 -s 1 -e 0.01 -q'); % we use linear SVM classifier (C = 1), calling libsvm library
models = train(TrnLabels, ftrain',  option);
LinearSVM_TrnTime = toc;
clear ftrain; 


%% PCANet Feature Extraction and Testing 

TestData_ImgCell = mat2imgcell(TestData,ImgSize,ImgSize,ImgFormat); % convert columns in TestData to cells 
clear TestData; 

fprintf('\n ====== PCANet Testing ======= \n')

nCorrRecog = 0;
RecHistory = zeros(nTestImg,1);

tic; 

predict_label = zeros(nTestImg,1);

for idx = 1:1:nTestImg
    
    ftest = PCANet_FeaExt(TestData_ImgCell(idx),V,PCANet); % extract a test feature using trained PCANet model 

    [xLabel_est, accuracy, decision_values] = predict(TestLabels(idx),...
        sparse(ftest'), models, '-q'); % label predictoin by libsvm
    
    predict_label(idx) = xLabel_est;
    
    if xLabel_est == TestLabels(idx)
        RecHistory(idx) = 1;
        nCorrRecog = nCorrRecog + 1;
    end
    
    if 0==mod(idx,nTestImg/100); 
        fprintf('Accuracy up to %d tests is %.2f%%; taking %.2f secs per testing sample on average. \n',...
            [idx 100*nCorrRecog/idx toc/idx]); 
    end 
    
    TestData_ImgCell{idx} = [];
    
end
Averaged_TimeperTest = toc/nTestImg;
Accuracy = nCorrRecog/nTestImg; 
ErRate = 1 - Accuracy;

%% Results display
fprintf('\n ===== Results of PCANet, followed by a linear SVM classifier =====');
fprintf('\n     PCANet training time: %.2f secs.', PCANet_TrnTime);
fprintf('\n     Linear SVM training time: %.2f secs.', LinearSVM_TrnTime);
fprintf('\n     Testing error rate: %.2f%%', 100*ErRate);
fprintf('\n     Average testing time %.2f secs per test sample. \n\n',Averaged_TimeperTest);


%% Saving the results in the submission file:
filename_submission = 'submission.csv';
disp(strcat('Creating submission file: ',filename_submission));
f = fopen(filename_submission, 'w');
fprintf(f,'%s,%s\n','ImageId','Label');
for i = 1 : length(predict_label)
    fprintf(f,'%d,%d\n',i,predict_label(i));
end
fclose(f);
disp('Done.');

    
