{
  appliance = {
    name = "miniserver";
    devices = {
      usbA = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:9:1.0-scsi-0:0:0:0";
      usbB = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:10:1.0-scsi-0:0:0:0";
      nvmeA = "/dev/disk/by-path/pci-0000:01:00.0-nvme-1";
      nvmeB = "/dev/disk/by-path/pci-0000:02:00.0-nvme-1";
      espPartUuidA = "6bf9a932-bd2a-4fc2-8096-6f26ebabdf87";
      espPartUuidB = "cccb4689-e094-4724-be4b-2573bcbcb0d1";
    };
    btrfs = {
      rootUuid = "cc18fbc1-72f8-4ba7-befe-415d3f5319af";
      rootPartUuidA = "765a40c3-182f-4235-84a5-66a2c5df793a";
      rootPartUuidB = "69176bdc-8038-49f5-b761-7e64bda24ea1";
      dataUuid = "2707225f-f83b-4421-939f-d7a8e3f2eb01";
      dataPartUuidA = "be00c21d-ab6f-4437-a75f-9b35dbc903be";
      dataPartUuidB = "d476006c-63a6-40a2-a4ec-a15c40edb6f7";
      swapPartUuidA = "aa875932-bb52-4ae0-84b4-fc69b97d9201";
      swapPartUuidB = "c3ee2c0b-9efd-4245-bcf9-ccd6422dca84";
    };
  };
}
