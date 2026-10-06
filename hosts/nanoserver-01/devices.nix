{
  appliance = {
    name = "nanoserver";

    devices = {
      usbA = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:2:1.0-scsi-0:0:0:0";
      usbB = "/dev/disk/by-path/pci-0000:00:14.0-usbv3-0:4:1.0-scsi-0:0:0:0";
      nvmeA = "/dev/disk/by-path/pci-0000:02:00.0-nvme-1";
      nvmeB = "/dev/disk/by-path/pci-0000:03:00.0-nvme-1";
      espPartUuidA = "8fe35b9e-2963-4d7e-9141-ae5bd71e25bb";
      espPartUuidB = "b2accbd5-1d48-4537-a5c9-5586005063cd";
    };

    btrfs = {
      rootUuid = "b93a88b1-2a5a-40e3-9eef-27c7411f1338";
      rootPartUuidA = "51aa9f94-d5de-4830-a23e-f3e57439d1f7";
      rootPartUuidB = "ba8795c3-596a-4f7c-a55c-56500682c2bb";
      dataUuid = "20c43ee3-b68f-43a7-a5e1-4ac052a4ae4d";
      dataPartUuidA = "a9017dab-6265-430b-9319-e7ffab84fecf";
      dataPartUuidB = "0428aa29-f5ce-471a-827e-5f8e9c205b6b";
      swapPartUuidA = "3095787b-0168-478d-ba78-964f7026f013";
      swapPartUuidB = "5a69e09c-4055-487b-ab31-43330d8e7cde";
    };
  };
}
