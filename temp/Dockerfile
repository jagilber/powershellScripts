#FROM lm-devops-docker.artifactory.hiscox.com/lm-ado-agent-base:latest
FROM ubuntu:18.04

# update apt and get apt-transport-https
# reference https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-get-started-linux
RUN apt-get update && apt-get install -y apt-transport-https
RUN apt-get install -y coreutils
RUN apt-get install -y wget
RUN apt-get install -y curl
RUN apt-get install -y tcpdump
RUN apt-get install -y gnupg2
RUN apt-get install -y iputils-ping
RUN apt-get install -y tree
RUN apt-get install -y software-properties-common
RUN apt-get update

RUN wget https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
RUN dpkg -i packages-microsoft-prod.deb
RUN apt update
RUN apt install -y dotnet-sdk-3.1

# install .Net Core SDK
#RUN apt-get update && apt-get install -y dotnet-sdk-3.1
ENV DotNetCore31SDK enabled

# install service fabric SDK
# Reference https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-get-started-linux?tabs=sdksetupubuntu%2Clocalclusteroneboxcontainer
#RUN curl https://raw.githubusercontent.com/Azure/service-fabric-scripts-and-templates/master/scripts/SetupServiceFabric/SetupServiceFabric.sh
ADD . /scripts
RUN sh ./scripts/sf-install.sh

ENV ServiceFabric enabled

CMD sleep 1000s