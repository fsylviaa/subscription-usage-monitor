figma.showUI(__html__,{width:720,height:530});
async function inspect(){
 const p=figma.root.children.find(x=>x.name==='01 · 可点击原型'),l=figma.root.children.find(x=>x.name==='02 · 组件与规范');
 await p.loadAsync();await l.loadAsync();
 const comps=l.findAllWithCriteria({types:['COMPONENT','COMPONENT_SET']});
 const styles=await figma.getLocalPaintStylesAsync();
 const fonts=await figma.listAvailableFontsAsync();
 const screens=p.findAllWithCriteria({types:['FRAME']}).filter(x=>/^(Light|Dark)\//.test(x.name));
 figma.ui.postMessage({status:'只读检查完成',pages:figma.root.children.map(x=>({id:x.id,name:x.name})),screenCount:screens.length,top:p.children.map(x=>({id:x.id,name:x.name,type:x.type,children:x.children?.length})),components:comps.map(x=>({id:x.id,name:x.name,type:x.type})),styles:styles.map(x=>({id:x.id,name:x.name})),fonts:fonts.filter(x=>['Inter','PingFang SC'].includes(x.fontName.family)).map(x=>x.fontName),reviews:screens.filter(x=>/\/(Review|Dashboard|Settings)$/.test(x.name)).map(x=>({id:x.id,name:x.name}))});
}
figma.ui.onmessage=async m=>{try{if(m.type==='close')return figma.closePlugin();if(m.type==='inspect'||m.type==='audit')await inspect();}catch(e){figma.ui.postMessage({status:'检查失败',error:String(e)});}};
inspect();
