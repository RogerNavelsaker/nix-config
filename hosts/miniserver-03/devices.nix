{
  appliance = {
    name = "miniserver";
    devices = {
      usbA = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:9:1.0-scsi-0:0:0:0";
      usbB = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:10:1.0-scsi-0:0:0:0";
      nvmeA = "/dev/disk/by-path/pci-0000:01:00.0-nvme-1";
      nvmeB = "/dev/disk/by-path/pci-0000:02:00.0-nvme-1";
      espPartUuidA = "5875a50d-1172-47f8-ae29-a7021b302601";
      espPartUuidB = "020a9889-db5f-44de-b2b0-f5d2313f5d70";
    };
    btrfs = {
      rootUuid = "0d5713e5-bd6c-409e-b630-64056b7286da";
      rootPartUuidA = "10467ca0-067d-4214-a4cf-d117d38cb288";
      rootPartUuidB = "2925739a-89be-478a-b26b-5347d41383cd";
      dataUuid = "8043cd0d-d3d7-478a-9db4-8f0008f81e57";
      dataPartUuidA = "bf9f27a6-e0c9-4a43-92dd-14a8a8091134";
      dataPartUuidB = "bfc662a9-19bc-4b68-8961-fdca45901380";
      swapPartUuidA = "6a512aa4-2834-495d-9c6f-80cb168d9b75";
      swapPartUuidB = "3d4d2ff5-7823-4570-a84a-beeac0281503";
    };
  };
}
