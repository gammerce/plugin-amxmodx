FROM cm2network/steamcmd

ARG metamod_version=1.20
ARG amxmod_version=1.8.2

# Install HLDS
RUN /home/steam/steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/steam/dedicated +app_update 90 validate +quit; exit 0
RUN /home/steam/steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/steam/dedicated +app_update 90 validate +quit; exit 0
RUN /home/steam/steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/steam/dedicated +app_update 90 validate +quit

RUN mkdir -p ~/.steam && ln -s /home/steam/dedicated ~/.steam/sdk32
RUN ln -s /home/steam/steamcmd/ /home/steam/dedicated/steamcmd
ADD server/files/steam_appid.txt /home/steam/dedicated/steam_appid.txt

# Add default config
# ADD files/server.cfg /opt/hlds/cstrike/server.cfg

# Install metamod
RUN mkdir -p /home/steam/dedicated/cstrike/addons/metamod/dlls
RUN curl -sqL "http://prdownloads.sourceforge.net/metamod/metamod-$metamod_version-linux.tar.gz?download" | tar -C /home/steam/dedicated/cstrike/addons/metamod/dlls -zxvf -
ADD server/files/liblist.gam /home/steam/dedicated/cstrike/liblist.gam
ADD server/files/plugins.ini /home/steam/dedicated/cstrike/addons/metamod/plugins.ini

# Install dproto
# RUN mkdir -p /home/steam/dedicated/cstrike/addons/dproto
# ADD files/dproto_i386.so /opt/hlds/cstrike/addons/dproto/dproto_i386.so
# ADD files/dproto.cfg /opt/hlds/cstrike/dproto.cfg

# Install AMX mod X
RUN curl -sqL "http://www.amxmodx.org/release/amxmodx-$amxmod_version-base-linux.tar.gz" | tar -C /home/steam/dedicated/cstrike/ -zxvf -
RUN curl -sqL "http://www.amxmodx.org/release/amxmodx-$amxmod_version-cstrike-linux.tar.gz" | tar -C /home/steam/dedicated/cstrike/ -zxvf -

# Add shopsms
RUN sed -i '1s/^/sklep_sms.amxx\n/' /home/steam/dedicated/cstrike/addons/amxmodx/configs/plugins.ini
ADD cstrike/addons/amxmodx/plugins/* /home/steam/dedicated/cstrike/addons/amxmodx/plugins/
ADD cstrike/addons/amxmodx/configs/* /home/steam/dedicated/cstrike/addons/amxmodx/configs/

WORKDIR /home/steam/dedicated

VOLUME /home/steam/dedicated

EXPOSE 27015

CMD /home/steam/dedicated/hlds_run -game cstrike +maxplayers 16 +map de_dust2
