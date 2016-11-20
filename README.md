# Generic Protobuf Dessector

This is a generic protobuf dessector for Wireshark.
Wireshark need build with LUA 5.2.

### Installation

Copy protobuf_dissector.lua into Wireshark user plugin directory.

### Usage

1. Use "Decode As..." specify UDP port to use protobuf dessector.

2. You can call protobuf dessctor in you own dessctor, following is a example in Wireshark lua API.

```lua
Dissector.get("protobuf"):call(buffer(4,payload_len):tvb(), pinfo, tree)
```
