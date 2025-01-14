library(MASS)
library(gplots)
library(ROCR)
library(ggplot2)
library(rARPACK)
library(limma)
library(netZooR)
library(RUVcorr)
library(sva)
library(glue)

## Imports

setwd("/Users/soel/Documents/cobra-experiments/") # Put your local path here
source('./experiments/simulation_2/diagnosis_plots.R')
source('./experiments/simulation_2/simulateData.R')
source('./experiments/simulation_2/generateMasterDF.R')

## Basic setup
sessionInfo <- sessionInfo()
seed <- sample(10000,1)
set.seed(seed) # use seed 1095 to reproduce Figure 2
numGenes <- 4000 
numSamples <-400
addedError <- 8
batchEffectMultiplier <- 2
path <- "figures/simulation_2/"

mu <- rnorm(numGenes,mean = 9)

batches <- c(rep(0,numSamples/2),rep(1,numSamples/2))
caseControl <- c(rep(0,numSamples/4),rep(1,numSamples/2),rep(0,numSamples/4))
X <- cbind(rep(1,numSamples),batches, caseControl)
blockSeq <- sample(LETTERS[1:10],50,replace=T)

study <- simulateStudy(numGenes=numGenes, numSamples=numSamples, addedError=addedError, 
                       blockSeq=blockSeq, mu=mu, caseControl=caseControl, batches=batches, batchEffectMultiplier)

# Recreate the truth
batchMat <- tcrossprod(study$trueEffects$batch1Effect) - tcrossprod(study$trueEffects$batch2Effect) 
realMat <- tcrossprod(study$trueEffects$casesEffect) - tcrossprod(study$trueEffects$controlsEffect)

truePairwiseLabels <- rep("Background",choose(numGenes,2))
truePairwiseLabels[batchMat[row(batchMat) > col(batchMat)]!=0] <- "Batch effect"
truePairwiseLabels[realMat[row(realMat) > col(realMat)]!=0] <- "Real effect"

trueGeneLabels <- rep("Background", numGenes)
trueGeneLabels[study$batchEffectedGenes] <- "Batch"
trueGeneLabels[study$realEffectedGenes] <- "Real"

coex <- cor(t(study$data))
diag(coex) <- NA
png(paste0(path,'/coex_heatmap.png'), width = 1600, height = 1200)
heatmap.2(coex[c(T,F,F,F),c(T,F,F,F)], Rowv = F, Colv = F, trace = "none", 
          labRow=trueGeneLabels[c(T,F,F,F)], col="bluered", dendrogram = "none", RowSideColors = cbPalette[as.factor(trueGeneLabels[c(T,F,F,F)])])
dev.off()

start.time <- Sys.time()
insilico_result <- cobra(X, study$data)
print(paste("COBRA in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))

start.time <- Sys.time()
differentialCorrelationNaive <- cor(t(insilico_result$G[,caseControl==1]))-cor(t(insilico_result$G[,caseControl==0]))
print(paste("Naive in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))

start.time <- Sys.time()
differentialCorrelationNaivewBatch <- 
  (cor(t(insilico_result$G[,caseControl==1&batches==1]))-cor(t(insilico_result$G[,caseControl==0&batches==1])) +
     cor(t(insilico_result$G[,caseControl==1&batches==0]))-cor(t(insilico_result$G[,caseControl==0&batches==0])))/2
print(paste("Naive with batch in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))

start.time <- Sys.time()
expr_limma <- removeBatchEffect(insilico_result$G, batches==1)
limma <- cor(t(expr_limma[,caseControl == 1])) - cor(t(expr_limma[,caseControl == 0]))
print(paste("Limma in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))

start.time <- Sys.time()
RUV <- t(RUVNaiveRidge(t(insilico_result$G), center=FALSE, seq_len(numGenes)[trueGeneLabels == "Background"], nu = 5, kW = 50))
RUV <- cor(t(RUV[,caseControl == 1])) - cor(t(RUV[,caseControl == 0]))
print(paste("RUVCorr in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))

start.time <- Sys.time()
expr_combat = ComBat(dat=insilico_result$G, batch=(batches==1), par.prior=TRUE, prior.plots=FALSE)
combat <- cor(t(expr_combat[,caseControl == 1])) - cor(t(expr_combat[,caseControl == 0]))
print(paste("ComBat in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))


start.time <- Sys.time()
nsv=num.sv(study$data,cbind(rep(1,numSamples),batches), method = "be")
pc_corrected = t(sva_network(t(study$data), 250))
sva <- cor(t(pc_corrected[,batches == 1])) - cor(t(pc_corrected[,batches == 0]))
print(paste("SVA in ",round(as.numeric(difftime(Sys.time(), start.time,units = "secs")),1), "seconds"))

insilico_MasterDF <- generateMasterDF(insilico_result, differentialCorrelationNaive, differentialCorrelationNaivewBatch, combat, limma, sva, RUV, truePairwiseLabels, maxPoints=800000)

plotEigenvectors(insilico_result, 
                 trueGeneLabels,
                 path, numEigenvectors=6)

mean(abs(insilico_MasterDF$newMeth[insilico_MasterDF$labels=="Real effect"]))
mean(abs(insilico_MasterDF$newMeth[insilico_MasterDF$labels=="Batch effect"]))

diagnosticPlots(insilico_MasterDF, path)
# remove large objects to enable GitHub saving
rm(list=c("coex", "differentialCorrelationNaive", "differentialCorrelationNaivewBatch", "truePairwiseLabels", "batchMat", "cobra_corrected", "combat", "correlationNaive", "correlationNaivewBatch", "differentialCorrelationsDF", "insilico_MasterDF", "limma", "methodPred", "onlyEffects", "realMat", "roc.methodPred", "RUV", "SigmaBatch1", "SigmaBatch2", "Sigmas", "sva", "data", "expr_combat", "expr_limma", "pc_corrected", "insilico_result"))