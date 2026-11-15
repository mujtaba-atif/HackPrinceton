"""Deterministic Blender production scene. Run through Blender MCP or blender -b -P."""
import bpy, math, json, random, os
from pathlib import Path
from mathutils import Vector
ROOT=Path(os.environ.get('IRIS_VIDEO_ROOT', str(Path(__file__).resolve().parents[1])))
FPS=int(os.environ.get('IRIS_FPS','60'))
FONT=ROOT/'assets/fonts/Nunito-ExtraBold.ttf'
REG=ROOT/'assets/fonts/Nunito-SemiBold.ttf'
random.seed(24)
COL={'navy':'092653','ink':'061B37','blue':'297FDB','sky':'72C7F5','ice':'E7F5FF','white':'FAFCFF','violet':'7389E5','teal':'4EA9C7'}
def rgb(h):
    h=COL.get(h,h); a=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4 for v in a)+(1,)
def mat(name,color,metal=0,rough=.3,emit=0):
    m=bpy.data.materials.new(name);m.diffuse_color=rgb(color);m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=rgb(color)
    b.inputs['Metallic'].default_value=metal;b.inputs['Roughness'].default_value=rough
    b.inputs['Emission Color'].default_value=rgb(color);b.inputs['Emission Strength'].default_value=emit
    return m
M={k:mat(k,k,0,.3,.1 if k in ['white','ice'] else 0) for k in COL}
M['metal']=mat('Anodized blue titanium','blue',.8,.2)
M['glass']=mat('Frosted blue glass','sky',.3,.22)
M['glass'].node_tree.nodes.get('Principled BSDF').inputs['Transmission Weight'].default_value=.25
M['glow']=mat('Ice light','sky',.15,.25,2)
M['black']=mat('Black display bezel','020A17',.25,.19)

def empty(name,loc=(0,0,0)):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;return o

def cube(name,loc,dims,material,bevel=.15,parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    b=o.modifiers.new('Soft machined edges','BEVEL');b.width=bevel;b.segments=6
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');o.data.materials.append(material)
    if parent:o.parent=parent
    return o

def sphere(name,loc,scale,material,parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,location=loc);o=bpy.context.object;o.name=name;o.scale=scale
    o.data.materials.append(material)
    for p in o.data.polygons:p.use_smooth=True
    if parent:o.parent=parent
    return o

def curve(name,coords,radius,material,parent=None):
    c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=16;c.bevel_depth=radius;c.bevel_resolution=4
    s=c.splines.new('BEZIER');s.bezier_points.add(len(coords)-1)
    for p,co in zip(s.bezier_points,coords):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.data.materials.append(material)
    if parent:o.parent=parent
    return o

def key(o,f,loc=None,rot=None,scale=None):
    if loc is not None:o.location=loc;o.keyframe_insert(data_path='location',frame=f)
    if rot is not None:o.rotation_euler=rot;o.keyframe_insert(data_path='rotation_euler',frame=f)
    if scale is not None:o.scale=scale;o.keyframe_insert(data_path='scale',frame=f)

def text(name,body,x,z,size=.6,color='white',parent=None,align='LEFT',delay=0,out=None,font=None):
    """Text that rises into place at `delay` seconds and, with `out`, sinks away again."""
    c=bpy.data.curves.new(name,'FONT');c.body=body;c.font=bpy.data.fonts.load(str(font or (FONT if size>.45 else REG)),check_existing=True);c.size=size;c.align_x=align;c.space_line=1.06;c.extrude=.004;c.bevel_depth=.002
    o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.location=(x,-1,z);o.rotation_euler=(math.pi/2,0,0);c.materials.append(M[color]);
    if parent:o.parent=parent
    if delay>=0:
        key(o,1,scale=(.001,.001,.001),loc=(x,-1,z-.3))
        if delay>0:key(o,1+int(delay*FPS),scale=(.001,.001,.001),loc=(x,-1,z-.3))
        key(o,1+int((delay+.55)*FPS),scale=(1,1,1),loc=(x,-1,z))
    if out is not None:
        key(o,1+int(out*FPS),scale=(1,1,1),loc=(x,-1,z))
        key(o,1+int((out+.35)*FPS),scale=(.001,.001,.001),loc=(x,-1,z+.25))
    return o

def screen(name,path,w,h,parent):
    # Rounded rectangle with exact UV mapping, front normal -Y.
    r=.22;verts=[]
    for cx,cz,a in [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),(-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]:
        for j in range(13):
            q=math.radians(a+j*90/12);verts.append((cx+r*math.cos(q),-.246,cz+r*math.sin(q)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],[list(range(len(verts)))]);mesh.update()
    uv=mesh.uv_layers.new()
    for p in mesh.polygons:
        for li in p.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=(v.x/w+.5,v.z/h+.5)
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.parent=parent
    m=bpy.data.materials.new(name+' texture');m.use_nodes=True;n=m.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputMaterial');e=n.new('ShaderNodeEmission');e.inputs['Strength'].default_value=1
    if path:
        tex=n.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(path),check_existing=True);m.node_tree.links.new(tex.outputs['Color'],e.inputs['Color'])
    else:e.inputs['Color'].default_value=(0,0,0,1)
    m.node_tree.links.new(e.outputs[0],out.inputs['Surface']);mesh.materials.append(m);return o

def phone(name,asset,loc,scale=1,yaw=0,tilt=0,duration=10,entrance='rise',at=0):
    """A phone that arrives once (rising, sliding or not at all) and then just floats: no spins."""
    p=empty(name,loc);p.scale=(scale,)*3
    cube(name+' titanium body',(0,0,0),(3.72,.42,8.02),M['metal'],.28,p)
    cube(name+' front bezel',(0,-.19,0),(3.64,.1,7.94),M['black'],.26,p)
    screen(name+' display',ROOT/'assets/screens'/asset if asset else None,3.55,7.74,p)
    cube(name+' button',(1.89,0,.7),(.065,.14,.7),M['metal'],.035,p)
    cube(name+' volume',(-1.89,0,1.5),(.065,.14,.6),M['metal'],.03,p)
    rot=(0,math.radians(tilt),math.radians(yaw));p.rotation_euler=rot
    if entrance=='none':return p
    f0=1+int(at*FPS);f1=f0+int(1.1*FPS)
    start={'rise':(loc[0],loc[1],loc[2]-11),'slide':(loc[0]+11,loc[1],loc[2]),'drop':(loc[0],loc[1],loc[2]+11)}[entrance]
    key(p,1,loc=start,rot=(rot[0],rot[1],rot[2]+.35));key(p,f0,loc=start,rot=(rot[0],rot[1],rot[2]+.35))
    key(p,f1,loc=loc,rot=rot)
    for fc in (p.animation_data.action.fcurves if hasattr(p.animation_data.action,'fcurves') else []):
        for kp in fc.keyframe_points:kp.interpolation='BACK'
    end=int(duration*FPS)
    if end>f1+FPS:
        key(p,end,loc=(loc[0],loc[1],loc[2]+.25),rot=(rot[0],rot[1],rot[2]+.04))
    return p

def backdrop(path,strength=.9,fade_in=0,fade_from=0):
    """A full-frame photo plate behind everything (the blurred, low-vision view of the table)."""
    w,h=19.4,10.92
    mesh=bpy.data.meshes.new('Photo plate');mesh.from_pydata([(-w/2,0,-h/2),(w/2,0,-h/2),(w/2,0,h/2),(-w/2,0,h/2)],[],[[0,1,2,3]]);mesh.update()
    uv=mesh.uv_layers.new()
    for li,(u,v) in zip(range(4),[(0,0),(1,0),(1,1),(0,1)]):uv.data[li].uv=(u,v)
    o=bpy.data.objects.new('Photo plate',mesh);bpy.context.collection.objects.link(o);o.location=(0,3,0)
    m=bpy.data.materials.new('Photo plate');m.use_nodes=True;n=m.node_tree.nodes;n.clear()
    out=n.new('ShaderNodeOutputMaterial');e=n.new('ShaderNodeEmission');t=n.new('ShaderNodeTexImage')
    t.image=bpy.data.images.load(str(ROOT/'assets/screens'/path),check_existing=True)
    m.node_tree.links.new(t.outputs['Color'],e.inputs['Color']);m.node_tree.links.new(e.outputs[0],out.inputs['Surface'])
    s=e.inputs['Strength']
    s.default_value=fade_from;s.keyframe_insert('default_value',frame=1)
    if fade_in>0:s.keyframe_insert('default_value',frame=1+int(fade_in*FPS))
    s.default_value=strength;s.keyframe_insert('default_value',frame=1+int((fade_in+1.6)*FPS))
    mesh.materials.append(m);return o

def mascot(name,loc,s=1,variant=0,duration=10):
    root=empty(name,loc);root.scale=(s,)*3
    color=['teal','violet','blue','sky'][variant]
    sphere(name+' soft body',(0,0,0),(.75,.44,1),M[color],root)
    for x in [-.46,.46]:
        sphere(name+' foot',(x,-.03,-.94),(.31,.33,.16),M['navy'],root)
        arm=sphere(name+' arm',(x*1.8,0,-.15),(.16,.19,.43),M[color],root);arm.rotation_euler[1]=x*.8
    eye_x=[0] if variant==2 else [-.3,.3]
    for i,x in enumerate(eye_x):
        e=sphere(name+' eye',(x,-.4,.28),(.34 if variant==2 else .25,.13,.4 if variant==2 else .32),M['white'],root)
        pupil=sphere(name+' pupil',(x+.035,-.525,.26),(.16,.055,.20),M['ink'],root)
        sphere(name+' glint',(x+.08,-.58,.34),(.045,.022,.045),M['ice'],root)
        # Eyelids close quickly once every few seconds.
        orig=e.scale.copy()
        for t in [2.3+variant*.35,6.4+variant*.4,10.4]:
            if t<duration:
                for dt,factor in [(-.10,1),(0,.06),(.12,1)]:
                    key(e,int((t+dt)*FPS),scale=(orig.x,orig.y,orig.z*factor))
    curve(name+' smile',[(-.22,-.44,-.25),(0,-.49,-.34),(.24,-.44,-.22)],.034,M['navy'],root)
    if variant==0:
        for x in [-.55,.55]:
            ear=sphere(name+' ear',(x,.02,.9),(.2,.2,.5),M[color],root);ear.rotation_euler[1]=x*.85
    if variant==1:
        for x in [-.3,.3]:
            curve(name+' glasses',[(x+.32*math.cos(a),-.57,.28+.39*math.sin(a)) for a in [j*2*math.pi/24 for j in range(25)]],.045,M['navy'],root)
        curve('bridge',[(-.06,-.57,.3),(.06,-.57,.3)],.05,M['navy'],root)
    if variant==2:
        cube(name+' lab coat',(0,-.11,-.55),(1.25,.65,.72),M['white'],.18,root)
        curve('coat lapel',[(-.45,-.46,-.22),(0,-.48,-.61),(.45,-.46,-.22)],.04,M['sky'],root)
        sphere('coat button',(0,-.47,-.75),(.045,.03,.045),M['blue'],root)
    if variant==3:
        curve(name+' headphone band',[(.85*math.cos(a),.02,.15+.95*math.sin(a)) for a in [j*math.pi/18 for j in range(19)]],.08,M['navy'],root)
        for x in [-.78,.78]:cube('ear cushion',(x,-.08,.2),(.23,.4,.6),M['navy'],.1,root)
    for j in range(int(duration/2)+2):
        t=min(duration,j*2);key(root,max(1,int(t*FPS)),loc=(loc[0]+.08*math.sin(j+variant),loc[1],loc[2]+.12*math.sin(j*1.7+variant)),rot=(0,.05*math.sin(j+variant),.05*math.cos(j+variant)))
    return root

def light(name,loc,power,size,color):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=rgb(color)[:3]
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,0))-o.location).to_track_quat('-Z','Y').to_euler()

def setup(name,duration,dark=False,chapter=None):
    scene=bpy.data.scenes.new(name);bpy.context.window.scene=scene
    scene.render.engine='BLENDER_EEVEE'
    scene.render.resolution_x=1920;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
    scene.render.fps=FPS;scene.frame_start=1;scene.frame_end=round(duration*FPS)
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB';scene.render.image_settings.color_depth='8';scene.render.image_settings.compression=15
    scene.render.film_transparent=False;scene.render.use_persistent_data=True
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
    scene.world=bpy.data.worlds.new(name+' world');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=rgb('ink' if dark else 'sky');scene.world.node_tree.nodes['Background'].inputs[1].default_value=.05 if dark else .2
    camd=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',camd);scene.collection.objects.link(cam);cam.location=(0,-30,0);cam.rotation_euler=(math.pi/2,0,0);camd.type='ORTHO';camd.ortho_scale=19.2;scene.camera=cam
    cube('Seamless midnight backdrop',(0,5,0),(60,.2,40),M['ink' if dark else 'navy'],.1)
    light('Softbox key',(-4,-8,9),1700,8,'ice');light('Blue rim',(6,1,6),2100,7,'sky');light('Violet fill',(-8,0,-2),1400,6,'violet')
    if not dark:
        for k in range(4):
            coords=[(-13+j*2.6,3.5+k*.25,-3.7+k*.32+math.sin(j*.7+k)*.7) for j in range(11)]
            o=curve('Flowing glass ribbon',coords,.045+k*.018,M['glow'] if k==0 else M['metal'])
            key(o,1,loc=(0,0,0));key(o,scene.frame_end,loc=(1.5,0,.5*math.sin(k)))
        for k in range(24):
            loc=(random.uniform(-10,10),random.uniform(2,4),random.uniform(-5,5));p=sphere('Ambient prism',loc,(.025,)*3,M['glow'])
            key(p,1,loc=loc);key(p,scene.frame_end,loc=(loc[0]+.8,loc[1],loc[2]+.65))
        text('Brand signature','I R I S',-8.45,4.35,.25,'sky',delay=-1)
        if chapter:text('Chapter',chapter,8.45,4.35,.20,'sky',align='RIGHT',delay=-1)
    return scene

def build():
    for s in list(bpy.data.scenes):
        if len(bpy.data.scenes)>1:bpy.data.scenes.remove(s)
    for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
    bpy.context.scene.name='Empty'
    shots=[]
    def shot(id,dur,**kw):
        sc=setup(id,dur,**kw);shots.append({'id':id,'duration':dur,'frames':round(dur*FPS)});return sc

    # --- Act 1: the problem, felt before it is explained ---------------------------------------
    shot('01_close_your_eyes',7,dark=True)
    backdrop('table-blur.png',.85,fade_in=3.2)
    text('Line one','Close your eyes.',0,.2,1.05,align='CENTER',delay=.5,out=2.9)
    text('Line two','Now find what you need.',0,.2,1.05,align='CENTER',delay=3.6)

    shot('02_every_day',7,dark=True)
    backdrop('table-blur.png',.85,fade_from=.85)
    text('Kicker','WHY WE BUILT IRIS',0,2.3,.3,'sky',align='CENTER',delay=.2)
    text('Line one','Some of our own family members\nlive with low vision.',0,1.1,.82,align='CENTER',delay=.5)
    text('Line two','For them, this is every day.',0,-1.9,.82,'sky',align='CENTER',delay=2.6)

    shot('03_scale',9,dark=True)
    backdrop('table-blur.png',.35,fade_from=.85)
    text('Kicker','THEY ARE NOT ALONE',0,3.35,.3,'sky',align='CENTER',delay=.2)
    text('Stat one','43 million',-4.6,1.0,1.35,align='CENTER',delay=.5)
    text('Stat one detail','people are blind',-4.6,-.05,.42,'ice',align='CENTER',delay=.8)
    text('Stat two','295 million',4.6,1.0,1.35,align='CENTER',delay=1.9)
    text('Stat two detail','live with moderate to\nsevere vision loss',4.6,-.05,.42,'ice',align='CENTER',delay=2.2)
    text('Projection','By 2050, over half a billion.',0,-2.3,.72,'sky',align='CENTER',delay=4.4)
    text('Source','IAPB Vision Atlas: 2020 estimates and 2050 projections (61M blind, 474M moderate to severe)',0,-4.5,.2,'ice',align='CENTER',delay=4.8)

    shot('04_the_gap',6,dark=True)
    backdrop('table-blur.png',.85,fade_from=.35)
    text('Line one','Most tools tell you\nwhat is in front of you.',0,1.0,.86,align='CENTER',delay=.3)
    text('Line two','Few get your hand to it.',0,-1.9,.95,'sky',align='CENTER',delay=2.4)

    # --- Act 2: Iris, and the moment the world comes into focus ---------------------------------
    shot('05_so_we_built_iris',6,dark=True)
    backdrop('table-blur.png',.85,fade_from=.85)
    text('Kicker','SO WE BUILT',-8,2.9,.3,'sky',delay=.2)
    text('Brand','Iris',-8.05,.75,2.4,delay=.35,font=FONT)
    text('Promise','Name what you need.\nIris finds it, and guides\nyour hand to it.',-8,-1.0,.48,'ice',delay=1.0)
    phone('Clarity','detect.png',(4.4,-.5,0),1.08,yaw=-8,tilt=-3,duration=6,entrance='rise',at=.6)

    shot('06_locate',5,chapter='LOCATE')
    text('Kicker','01 / LOCATE',-8,3.0,.28,'sky',delay=.1)
    text('Headline','Say “locate.”\nName the object.',-8,1.55,.95,delay=.25)
    text('Supporting line','Voice-first. No screen needed.',-8,-1.75,.36,'ice',delay=.6)
    phone('Options','options.png',(4.2,0,0),.98,yaw=-10,tilt=-4,duration=5,entrance='slide',at=.1)

    # The real recording is composited into this phone's display by assemble.py.
    shot('07_real_demo',DEMO,chapter='REAL APP FOOTAGE')
    phone('Live demonstration',None,(0,0,0),DEMO_SCALE,entrance='none')
    text('Kicker','LIVE ON IPHONE',-8.4,3.0,.26,'sky',delay=-1)
    beats=[(0,'Say what\nyou need.'),(4.6,'Iris guides\nyour hand.'),(12.8,'Take hold.'),(17.0,'Bring it\nclose.'),(22.4,'Hear what\nit is.')]
    for i,(t,line) in enumerate(beats):
        nxt=beats[i+1][0]-.4 if i+1<len(beats) else None
        text('Beat',line,-8.4,1.6,.78,delay=t+.15,out=nxt)
    notes=[(4.8,'Outline traced live\nfrom segmentation'),(7.0,'Fingertip-to-object\ndistance with LiDAR'),(22.6,'Label read on-device,\nexplained in Iris’s voice')]
    for i,(t,line) in enumerate(notes):
        z=1.9-i*1.45 if i<2 else 1.9
        out=21.8 if i<2 else None
        text('Note',line,4.15,z,.34,'ice',delay=t,out=out)

    # --- Act 3: how, and where it goes ---------------------------------------------------------
    shot('08_under_the_surface',9,chapter='UNDER THE SURFACE')
    text('Kicker','UNDER THE SURFACE',-8,3.4,.28,'sky')
    text('Headline','Vision. Depth. Voice.',-8,2.3,1.0,delay=.2)
    for i,(title,desc) in enumerate([('On-device vision','Segments and outlines 80 kinds of everyday objects.'),('LiDAR-assisted guidance','Measures fingertip to object, step by step.'),('ElevenLabs voice','Speaks, reads the label, and answers questions.')]):
        z=.75-i*1.5;cube('Technology glass panel',(0,.4,z),(16,.14,1.25),M['metal'],.25)
        text('Layer number','0'+str(i+1),-7.5,z-.15,.55,'sky',delay=.4+i*.4)
        text('Layer title',title,-5.9,z+.1,.48,delay=.45+i*.4)
        text('Layer explanation',desc,-5.9,z-.42,.28,'ice',delay=.55+i*.4)

    shot('09_next',12,chapter='WHAT IS NEXT')
    text('Kicker','WHERE IT GOES NEXT',-8,3.4,.28,'sky')
    text('Headline','Built for people we love.',-8,2.3,.95,delay=.2)
    for i,(title,desc) in enumerate([('Test it with our families','Real homes, real kitchens, real feedback.'),('Guidance on every iPhone','Depth estimated from the camera, no LiDAR needed.'),('Read what matters most','Medication and allergy labels, read with care.')]):
        z=.75-i*1.5;cube('Roadmap glass panel',(0,.4,z),(16,.14,1.25),M['metal'],.25)
        text('Roadmap number','0'+str(i+1),-7.5,z-.15,.55,'sky',delay=.8+i*.7)
        text('Roadmap title',title,-5.9,z+.1,.48,delay=.85+i*.7)
        text('Roadmap detail',desc,-5.9,z-.42,.28,'ice',delay=.95+i*.7)
    text('Stakes','1.8 billion people are expected to live with vision loss by 2050. (Lancet Global Health Commission)',0,-3.4,.27,'ice',align='CENTER',delay=3.4)

    shot('10_iris',7)
    text('Closing brand','Iris',-5.9,1.65,2.6,delay=.1)
    text('Closing promise','See beyond the surface.',-5.8,.35,.60,delay=.5)
    text('Closing detail','Find. Reach. Understand.',-5.8,-.45,.32,'sky',delay=.8)
    text('Event','Built at HackPrinceton 2026',-5.8,-1.25,.26,'ice',delay=1.1)
    phone('Final hero','welcome.png',(4,0,0),.94,yaw=-10,tilt=-4,duration=7,entrance='drop',at=.2)
    for i in range(4):mascot('Crew '+str(i),(-6.3+i*1.5,-.2,-2.8),.62,i,7)

    for sh in shots:
        sc=bpy.data.scenes[sh['id']]
        if sh['id']=='07_real_demo':continue
        cam=sc.camera
        # A slow push in on every shot, never the same direction twice in a row.
        side=1 if shots.index(sh)%2 else -1
        for f,loc,ortho in [(1,(-.5*side,-30,.2),19.2),(sc.frame_end,(.5*side,-30,-.1),18.2)]:
            rot=(Vector((0,0,0))-Vector(loc)).to_track_quat('-Z','Y').to_euler()
            key(cam,f,loc=loc,rot=rot);cam.data.ortho_scale=ortho;cam.data.keyframe_insert('ortho_scale',frame=f)
    bpy.context.window.scene=bpy.data.scenes['01_close_your_eyes'];bpy.context.scene.frame_set(int(5*FPS))
    for image in bpy.data.images:
        if image.source=='FILE' and image.filepath:image.filepath=bpy.path.relpath(image.filepath,start=str(ROOT/'scenes'))
    for font in bpy.data.fonts:
        if font.filepath and font.filepath!='<builtin>':
            try:font.pack()
            except Exception:pass
    for sc in bpy.data.scenes:
        sc.render.engine='BLENDER_EEVEE';sc.eevee.taa_render_samples=SAMPLES
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'scenes/iris-film.blend'))
    # Display aperture of the demo phone, in output pixels (1920 x 1080; ortho 19.2 units across).
    px=1920/19.2;sw=round(3.55*DEMO_SCALE*px);sh=round(7.74*DEMO_SCALE*px)
    total=sum(s['duration'] for s in shots)
    starts={};t=0
    for s in shots:starts[s['id']]=t;t+=s['duration']
    (ROOT/'shot-manifest.json').write_text(json.dumps({'fps':FPS,'resolution':[1920,1080],'duration':total,'starts':starts,
        'demo':{'duration':DEMO,'segments':DEMO_SEGMENTS},
        'demo_screen_pixels':{'x':960-sw//2,'y':540-sh//2,'width':sw,'height':sh},'shots':shots},indent=2))
    print('IRIS_SCENES_READY',len(shots),total)

# The demo: "Locate object selected / What do you want to find?" (13.5–16.6 s of the recording), then
# from the moment guidance starts (22.4 s) to the end of the answer. The silent wait between is cut.
DEMO_SEGMENTS=[[13.5,16.6],[22.4,53.5]]
DEMO=round(sum(b-a for a,b in DEMO_SEGMENTS),2)
DEMO_SCALE=1.1
SAMPLES=int(os.environ.get('IRIS_SAMPLES','16'))

if __name__=='__main__':build()
