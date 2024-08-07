{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:

{
  systemd.tmpfiles.rules = [
    "L+ /run/gdm/.config/monitors.xml - - - - ${pkgs.writeText "gdm-monitors.xml" ''
      <!-- this should all be copied from your ~/.config/monitors.xml -->
    <monitors version="2">
      <configuration>
        <logicalmonitor>
          <x>2160</x>
          <y>0</y>
          <scale>2</scale>
          <primary>yes</primary>
          <transform>
            <rotation>left</rotation>
            <flipped>no</flipped>
          </transform>
          <monitor>
            <monitorspec>
              <connector>DP-1</connector>
              <vendor>DEL</vendor>
              <product>DELL U2718Q</product>
              <serial>4K8X78AB1J6L</serial>
            </monitorspec>
            <mode>
              <width>3840</width>
              <height>2160</height>
              <rate>59.997</rate>
            </mode>
          </monitor>
        </logicalmonitor>
        <logicalmonitor>
          <x>0</x>
          <y>0</y>
          <scale>2</scale>
          <transform>
            <rotation>left</rotation>
            <flipped>no</flipped>
          </transform>
          <monitor>
            <monitorspec>
              <connector>DP-3</connector>
              <vendor>DEL</vendor>
              <product>DELL U2718Q</product>
              <serial>4K8X796K0MLL</serial>
            </monitorspec>
            <mode>
              <width>3840</width>
              <height>2160</height>
              <rate>59.997</rate>
            </mode>
          </monitor>
        </logicalmonitor>
        <logicalmonitor>
          <x>4320</x>
          <y>0</y>
          <scale>2</scale>
          <transform>
            <rotation>left</rotation>
            <flipped>no</flipped>
          </transform>
          <monitor>
            <monitorspec>
              <connector>DP-2</connector>
              <vendor>DEL</vendor>
              <product>DELL U2718Q</product>
              <serial>4K8X799T0L2L</serial>
            </monitorspec>
            <mode>
              <width>3840</width>
              <height>2160</height>
              <rate>59.997</rate>
            </mode>
          </monitor>
        </logicalmonitor>
      </configuration>
    </monitors>

    ''}"
  ];

}
