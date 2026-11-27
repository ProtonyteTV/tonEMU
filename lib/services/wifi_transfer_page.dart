// lib/services/wifi_transfer_page.dart

/// The page a PC browser sees at http://<phone-ip>:<port>/ . Self-contained (no external files).
/// Uploads each file with one POST /upload?path=<relative path>, then calls POST /finish.
const String kWifiTransferPage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>tonEMU Wi-Fi Transfer</title>
<style>
:root{--bg:#f2f2f7;--card:#fff;--text:#111;--sub:#6c6c70;--line:#d9d9de;--acc:#007aff;--ok:#34c759;--bad:#ff3b30;--bar:#e5e5ea}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--text:#fff;--sub:#8e8e93;--line:#38383a;--acc:#0a84ff;--bar:#2c2c2e}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:28px 18px 60px}
h1{font-size:26px;margin:0 0 4px}
.sub{color:var(--sub);margin:0 0 20px}
.card{background:var(--card);border-radius:16px;padding:18px;margin-bottom:16px;border:1px solid var(--line)}
#drop{border:2px dashed var(--line);text-align:center;padding:38px 16px;transition:.15s}
#drop.over{border-color:var(--acc);background:rgba(0,122,255,.07)}
#drop b{font-size:17px}
.btns{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-top:16px}
button{background:var(--acc);color:#fff;border:0;border-radius:10px;padding:10px 18px;font-size:15px;font-weight:600;cursor:pointer}
button.alt{background:var(--bar);color:var(--text)}
button:disabled{opacity:.5;cursor:default}
.hint{color:var(--sub);font-size:13px;margin-top:12px}
#overall{display:none}
.bar{height:8px;border-radius:4px;background:var(--bar);overflow:hidden;margin:8px 0}
.bar i{display:block;height:100%;width:0;background:var(--acc);transition:width .15s}
#list{max-height:300px;overflow:auto;font-size:13px}
.row{display:flex;justify-content:space-between;gap:10px;padding:5px 0;border-top:1px solid var(--line)}
.row span:first-child{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ok{color:var(--ok)}.bad{color:var(--bad)}
#result{display:none}
#result ul{margin:6px 0 0;padding-left:20px}
</style>
</head>
<body>
<main>
  <h1>tonEMU Wi-Fi Transfer</h1>
  <p class="sub">Send games from this computer to your phone. Keep the tonEMU import screen open on the phone.</p>

  <div class="card" id="drop">
    <b>Drop game files or folders here</b>
    <div class="hint">ROMs and .cue + .bin sets</div>
    <div class="btns">
      <button id="pickFiles">Choose files</button>
      <button id="pickFolder" class="alt">Choose a folder</button>
    </div>
    <input id="fi" type="file" multiple hidden>
    <input id="di" type="file" webkitdirectory directory multiple hidden>
  </div>

  <div class="card" id="overall">
    <div id="status">Uploading…</div>
    <div class="bar"><i id="bar"></i></div>
    <div class="hint" id="detail"></div>
    <div id="list"></div>
  </div>

  <div class="card" id="result"></div>
</main>
<script>
var K=new URLSearchParams(location.search).get("k")||"";
(function(){
  var $=function(i){return document.getElementById(i)};
  var JUNK=/(^|\/)(\.DS_Store|Thumbs\.db|desktop\.ini|\._[^\/]*)$/i;
  var queue=[], active=0, MAX=3, total=0, totalBytes=0, doneBytes=0, doneFiles=0, failed=0, running=false;
  var progress={};

  function fmt(n){if(n<1024)return n+" B";if(n<1048576)return (n/1024).toFixed(0)+" KB";if(n<1073741824)return (n/1048576).toFixed(1)+" MB";return (n/1073741824).toFixed(2)+" GB"}
  function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]})}

  function add(file,rel){
    rel=(rel||file.name).replace(/\\/g,"/").replace(/^\/+/,"");
    if(JUNK.test(rel))return;
    queue.push({file:file,rel:rel});
    total++;totalBytes+=file.size;
  }

  function start(){
    if(running)return;
    if(!queue.length)return;
    running=true;
    $("overall").style.display="block";
    $("result").style.display="none";
    $("list").innerHTML="";
    pump();
  }

  function pump(){
    while(active<MAX&&queue.length){send(queue.shift())}
    refresh();
    if(!active&&!queue.length&&running){finish()}
  }

  function send(item){
    active++;
    var row=document.createElement("div");row.className="row";
    row.innerHTML="<span>"+esc(item.rel)+"</span><span>0%</span>";
    $("list").appendChild(row);
    var x=new XMLHttpRequest();
    x.open("POST","/upload?k="+encodeURIComponent(K)+"&path="+encodeURIComponent(item.rel));
    x.upload.onprogress=function(e){
      if(e.lengthComputable){
        progress[item.rel]=e.loaded;
        row.lastChild.textContent=Math.round(e.loaded*100/e.total)+"%";
        refresh();
      }
    };
    x.onload=function(){
      active--;delete progress[item.rel];
      if(x.status===200){doneBytes+=item.file.size;doneFiles++;row.lastChild.textContent="done";row.lastChild.className="ok"}
      else{failed++;row.lastChild.textContent="failed";row.lastChild.className="bad"}
      pump();
    };
    x.onerror=function(){active--;delete progress[item.rel];failed++;row.lastChild.textContent="failed";row.lastChild.className="bad";pump()};
    x.send(item.file);
  }

  function refresh(){
    var cur=0;for(var k in progress)cur+=progress[k];
    var pct=totalBytes?Math.min(100,Math.round((doneBytes+cur)*100/totalBytes)):0;
    $("bar").style.width=pct+"%";
    $("status").textContent="Uploading "+(doneFiles+failed)+" / "+total+" files ("+pct+"%)";
    $("detail").textContent=fmt(doneBytes+cur)+" of "+fmt(totalBytes);
  }

  function finish(){
    $("status").textContent="Sorting into your library…";
    var x=new XMLHttpRequest();
    x.open("POST","/finish?k="+encodeURIComponent(K));
    x.onload=function(){
      running=false;
      var r={};try{r=JSON.parse(x.responseText)}catch(e){}
      show(r);reset();
    };
    x.onerror=function(){running=false;$("status").textContent="Lost connection to the phone.";reset()};
    x.send("");
  }

  function reset(){queue=[];total=0;totalBytes=0;doneBytes=0;doneFiles=0;failed=0;progress={}}

  function show(r){
    var h="<b>Transfer finished</b><ul>";
    var n=(r.imported||[]).length;
    h+="<li>"+n+" game(s) added to your library</li>";
    if(r.duplicates)h+="<li>"+r.duplicates+" already on the phone (skipped)</li>";
    if(failed)h+="<li class='bad'>"+failed+" file(s) failed to upload</li>";
    (r.warnings||[]).forEach(function(w){h+="<li class='bad'>"+esc(w)+"</li>"});
    if(r.ignoredCount)h+="<li>"+r.ignoredCount+" unsupported file(s) ignored: "+esc((r.ignored||[]).slice(0,4).join(", "))+(r.ignoredCount>4?"…":"")+"</li>";
    h+="</ul>";
    $("result").innerHTML=h;$("result").style.display="block";
    $("overall").style.display="none";
  }

  // pickers
  $("pickFiles").onclick=function(){$("fi").click()};
  $("pickFolder").onclick=function(){$("di").click()};
  $("fi").onchange=function(e){for(var i=0;i<e.target.files.length;i++)add(e.target.files[i]);e.target.value="";start()};
  $("di").onchange=function(e){for(var i=0;i<e.target.files.length;i++){var f=e.target.files[i];add(f,f.webkitRelativePath||f.name)}e.target.value="";start()};

  // drag & drop (files and whole folders)
  var drop=$("drop");
  ["dragenter","dragover"].forEach(function(ev){drop.addEventListener(ev,function(e){e.preventDefault();drop.classList.add("over")})});
  ["dragleave","drop"].forEach(function(ev){drop.addEventListener(ev,function(e){e.preventDefault();drop.classList.remove("over")})});
  drop.addEventListener("drop",function(e){
    var items=e.dataTransfer.items;
    if(items&&items.length&&items[0].webkitGetAsEntry){
      var pending=0,entries=[];
      for(var i=0;i<items.length;i++){var en=items[i].webkitGetAsEntry();if(en)entries.push(en)}
      var walk=function(en,path){
        pending++;
        if(en.isFile){en.file(function(f){add(f,path+f.name);if(--pending===0)start()},function(){if(--pending===0)start()})}
        else{
          var rd=en.createReader();
          var all=[];
          var more=function(){rd.readEntries(function(list){
            if(list.length){all=all.concat(list);more()}
            else{all.forEach(function(c){walk(c,path+en.name+"/")});if(--pending===0)start()}
          },function(){if(--pending===0)start()})};
          more();
        }
      };
      entries.forEach(function(en){walk(en,"")});
    }else{
      for(var j=0;j<e.dataTransfer.files.length;j++)add(e.dataTransfer.files[j]);
      start();
    }
  });
  window.addEventListener("dragover",function(e){e.preventDefault()});
  window.addEventListener("drop",function(e){e.preventDefault()});
})();
</script>
</body>
</html>
''';
