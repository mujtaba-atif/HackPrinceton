import bpy
bpy.ops.preferences.addon_enable(module='blender_mcp')
bpy.ops.wm.save_userpref()
if not getattr(bpy.context.scene, 'blendermcp_server_running', False):
    bpy.ops.blendermcp.start_server()
