# ZTP For Telco Edge 5G

Here we will collect all the info around the ZTP flow, which are the preferred scenarios, the steps to follow and much more. Let's get started from the beggining with some context and theory.

## What is ZTP?

ZTP stands for Zero Touch Provisioning, a project to deploy and deliver Openshift 4 in a HUB-SPOKE architecture (in a relation of 1-N), where the HUB will manage many Spokes. The Hub and the Spokes will be based on Openshift 4 but with the difference that the HUB cluster will manage and deploy the spokes using RH ACM (Red Hat Advanced Cluster Management).

**Why Zero Touch Provisioning If I need to deploy some things by hand?**, well this is a fair question, we need to have a consistent base for the hub to perform the Spoke deployments and for that we need to deploy OCP4 (On a IPI way) if not we will have the egg-chicken issue.

**Why is this related with Single Node Openshift (SNO) and Remote Worker Node (RWN)?**, in the 5G world exists some areas called RAN (Radio Access Network) here we have some scenarios but the important points here is, SNO will be mostly on the D-RAN places and eventually on C-RAN ones, this happens in the same way with RWN.

## Context on ZTP architecture

On a high level view we have 2 scenarios, the connected world and the disconnected world which means, that your OCP nodes can access directly to Internet or not. From here we need to separate them in 2 ways to follow. the disconnected one will need to fill some prerequistes before the action starts, let's take a look to some diagrams:

### Disconnected ZTP Flow

![](https://i.imgur.com/eCLCzpA.png)

### Connected ZTP Flow

![](https://i.imgur.com/0BqWhRk.png)


These are the steps 1-by-1 that we need to follow in order to deploy every element of ZTP, including the Hub and the Spoke cluster. As you see, there are some differencies between those but mostly on the pre-requisites side.

### ZTP Hub Components

Here we will need some basic components, the OCP Hub cluster will need at least:

- OCP4 in a IPI deployment way (which includes Metal3 pods)
- Storage to work with (3 PVs at least to deploy ACM)
- ACM Software available (v2.3.0)
    - Hive
    - Assisted Installer
- The manifests to create the Spoke clusters
- The BareMetalNodes to deploy OCP on top of them


## How to start with ZTP?

Well, we can discover how to deal with ZTP following these steps:

1. Disconnected ZTP Flow Hub deployment
2. Connected ZTP Flow Hub deployment