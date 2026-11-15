"""Use the actual Blender MCP server through stdio, even before a client restart."""
import asyncio, json, sys
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    params = StdioServerParameters(command='/opt/homebrew/bin/uvx', args=['mcp-for-blender'])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            if len(sys.argv) == 1:
                result = await session.list_tools()
                print(json.dumps([{'name':t.name,'schema':t.input_schema} for t in result.tools], indent=2))
            else:
                if sys.argv[1]=='--script':
                    path=Path(sys.argv[2]).resolve()
                    code="exec(compile("+repr(path.read_text())+", "+repr(str(path))+", 'exec'), "+repr({"__name__":"__main__","__file__":str(path)})+")"
                    result=await session.call_tool('execute_blender_code',{'code':code,'user_prompt':'Build the approved Iris demo scenes.'})
                else:
                    result = await session.call_tool(sys.argv[1], json.loads(sys.argv[2]))
                for c in result.content:
                    if hasattr(c,'text'): print(c.text)
                if getattr(result, "is_error", False): raise SystemExit(1)

asyncio.run(main())
