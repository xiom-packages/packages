module xiom.vulkan.wrapper

pub type VulkanInstance = {
  handle: Int;
  debug: Bool;
} derive[Clone]

pub type VulkanDevice = {
  handle: Int;
  physical: Int;
} derive[Clone]

fn vk_create_instance(app_name: Str) -> Result[VulkanInstance, Str]
  requires: app_name.len() > 0
  ensures: result.is_ok() implies result.unwrap().handle != 0
{
  let raw = create_instance(app_name, "XIOM Engine");
  match raw {
    Ok(handle) => Ok(VulkanInstance { handle: handle; debug: false; }),
    Err(e) => Err(e),
  }
}

fn vk_destroy_instance(instance: VulkanInstance)
  requires: instance.handle != 0
{
  destroy_instance(instance.handle);
}

fn vk_enumerate_devices(instance: &VulkanInstance) -> Result[Vec[Int], Str]
  requires: instance.handle != 0
{
  enumerate_devices(instance.handle)
}

fn vk_create_device(instance: &VulkanInstance, physical_device: Int) -> Result[VulkanDevice, Str]
  requires: instance.handle != 0
  requires: physical_device != 0
  ensures: result.is_ok() implies result.unwrap().handle != 0
{
  let raw = create_device(physical_device);
  match raw {
    Ok(handle) => Ok(VulkanDevice { handle: handle; physical: physical_device; }),
    Err(e) => Err(e),
  }
}

fn vk_destroy_device(device: VulkanDevice)
  requires: device.handle != 0
{
  destroy_device(device.handle);
}

fn vk_get_device_name(device: &VulkanDevice) -> Str
  requires: device.handle != 0
{
  get_device_name(device.physical)
}

fn vk_get_device_type(device: &VulkanDevice) -> Int
  requires: device.handle != 0
{
  get_device_type(device.physical)
}

fn vk_wait_device_idle(device: &VulkanDevice)
  requires: device.handle != 0
{
  wait_device_idle(device.handle);
}
