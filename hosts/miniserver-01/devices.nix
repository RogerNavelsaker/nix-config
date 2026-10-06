{
  appliance = {
    name = "miniserver";
    devices = {
      usbA = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:9:1.0-scsi-0:0:0:0";
      usbB = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:10:1.0-scsi-0:0:0:0";
      nvmeA = "/dev/disk/by-path/pci-0000:01:00.0-nvme-1";
      nvmeB = "/dev/disk/by-path/pci-0000:02:00.0-nvme-1";
      espPartUuidA = "c9845acf-f04e-42f0-a2b4-a63479d2272f";
      espPartUuidB = "ffa84e4c-2aaf-47e0-876c-64850c0a622f";
    };
    btrfs = {
      rootUuid = "669d2e7d-198b-4548-8638-55865977f704";
      rootPartUuidA = "e9785a73-6a43-46f0-9198-2903fb97ec39";
      rootPartUuidB = "6ec23c98-0b77-4b9e-ba35-af9dc23104c7";
      dataUuid = "35af8d4c-2c74-4a6e-ab20-7942419f977a";
      dataPartUuidA = "07498d40-9646-4586-8f54-0283a4f5eff2";
      dataPartUuidB = "8e1147fe-a3d0-4259-995d-48954eb59039";
      swapPartUuidA = "273b0e79-5bcc-431b-8243-5d413b723704";
      swapPartUuidB = "98320b39-9137-4c7c-a7dc-aa50875f7683";
    };
  };
}
