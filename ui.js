let jailInterval = null;
let maxUnits = 6;
let currentUnits = 1;
let currentTarget = '';
let actionBusy = false;

const suspectLabels = {
    requestId: ['Solicitar licencia / ID', 'Identifica al sospechoso y muestra sus datos.'],
    vehicleSearch: ['Buscar ilegales en vehículo', 'Inspecciona el vehículo y al ocupante.'],
    search: ['Registrar individuo', 'El agente registra al sospechoso.'],
    follow: ['Sígueme', 'El sospechoso sigue al agente.'],
    wrist: ['Agarrar de las muñecas / Soltar', 'Sujeta o libera al sospechoso.'],
    face: ['Mírame', 'Hace que el sospechoso mire al agente.'],
    releaseDrive: ['Liberar — conducir', 'Libera al sospechoso y lo deja conducir.'],
    releaseWalk: ['Liberar — caminar', 'Libera al sospechoso y lo deja caminar.'],
    detain: ['Detener (esposar)', 'Esposa y detiene al sospechoso.'],
    uncuff: ['Desesposar', 'Quita las esposas al sospechoso.'],
    placeCar: ['Meter en vehículo', 'Coloca al sospechoso en el vehículo policial.'],
    jail: ['Enviar a prisión', 'Traslada al sospechoso al sistema de cárcel.']
};

const orderLabels = {
    backup: ['Respaldo', 'Envia unidades a tu posición.'],
    investigate: ['Investigar', 'Investiga una zona o incidente.'],
    patrol: ['Patrulla', 'Envía una patrulla preventiva.'],
    trafficStop: ['Parada de tráfico', 'Unidad intenta detener al objetivo.'],
    pursuit: ['Persecución', 'Unidades persiguen al objetivo.'],
    spikes: ['Pinchos', 'Despliega pinchos en el objetivo.'],
    roadblock: ['Bloqueo', 'Crea un bloqueo policial en la zona.'],
    tactical: ['Unidad táctica', 'Envía SWAT para una situación peligrosa.'],
    helicopter: ['Helicóptero', 'Solicita apoyo aéreo.'],
    military: ['Militar', 'Solicita respuesta militar.'],
    transport: ['Transporte / arresto', 'Envía una unidad para detener y procesar.'],
    clearUnits: ['Retirar unidades', 'Retira las unidades AI bajo tu mando.']
};

function nui(name, body={}) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)
    });
}

function closeMenu() { nui('policeMenuClose'); }

function renderSuspectActions() {
    const root=document.getElementById('suspect-actions');
    root.innerHTML='';
    Object.keys(suspectLabels).forEach(key=>{
        const info=suspectLabels[key];
        const btn=document.createElement('button');
        btn.type='button';
        btn.className=`suspect-action ${key==='jail' || key==='detain' ? 'danger':''}`;
        btn.innerHTML=`<span class="sa-title">${info[0]}</span><span class="sa-desc">${info[1]}</span>`;
        btn.onclick=()=>{
            const selected=document.getElementById('target-select').value || '';
            if(selected) currentTarget=selected;
            if(!currentTarget){
                document.getElementById('status').innerText='Selecciona primero al sospechoso.';
                return;
            }
            if(actionBusy) return;
            actionBusy=true;
            btn.disabled=true;
            document.getElementById('status').innerText=`Enviando orden: ${info[0]}...`;
            nui('policeSuspectAction',{action:key,targetId:currentTarget,units:currentUnits});
            setTimeout(()=>{ actionBusy=false; btn.disabled=false; },150);
        };
        root.appendChild(btn);
    });
}

function renderOrders(orders) {
    const root = document.getElementById('orders');
    root.innerHTML = '';
    Object.keys(orderLabels).forEach(key => {
        if (orders && orders[key] === false) return;
        const info = orderLabels[key];
        const btn = document.createElement('button');
        btn.className = `order ${key === 'clearUnits' ? 'danger' : ''}`;
        btn.innerHTML = `<span class="order-title">${info[0]}</span><span class="order-desc">${info[1]}</span>`;
        btn.onclick = () => {
            currentTarget = document.getElementById('target-select').value || '';
            nui('policeMenuOrder', {order:key, units:currentUnits, targetId:currentTarget});
        };
        root.appendChild(btn);
    });
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'updateStars') {
        const container = document.getElementById('stars-container');
        const starsDiv = document.getElementById('stars');
        starsDiv.innerHTML = '';
        if (data.stars <= 0) { container.classList.add('hidden'); return; }
        container.classList.remove('hidden');
        for (let i=1;i<=7;i++) {
            const star=document.createElement('div');
            star.className=i<=data.stars?'star':'star empty';
            starsDiv.appendChild(star);
        }
    }

    if (data.action === 'openPoliceMenu') {
        actionBusy = false;
        currentTarget = '';
        maxUnits = Number(data.maxUnits || 6);
        const slider=document.getElementById('units');
        slider.max=maxUnits; slider.value=1; currentUnits=1;
        document.getElementById('units-value').innerText='1';
        renderOrders(data.orders || {});
        renderSuspectActions();
        document.getElementById('suspect-panel').classList.add('hidden');
        document.getElementById('police-menu').classList.remove('hidden');
        document.getElementById('status').innerText='Listo para recibir órdenes.';
    }

    if (data.action === 'closePoliceMenu') {
        actionBusy = false;
        document.getElementById('police-menu').classList.add('hidden');
    }

    if (data.action === 'policeTargets') {
        const select=document.getElementById('target-select');
        const previous = currentTarget || select.value || '';
        select.innerHTML='<option value="">Selecciona una persona</option>';
        (data.targets || []).forEach(t => {
            const o=document.createElement('option');
            o.value=t.id; o.textContent=`[${t.id}] ${t.name} — ${Math.round(t.distance)}m`;
            select.appendChild(o);
        });
        // Al abrir F6, el primer objetivo detectado por el rayo de cámara queda
        // seleccionado automáticamente. El jugador puede cambiarlo manualmente.
        if (previous && [...select.options].some(o => o.value === previous)) {
            select.value = previous;
            currentTarget = previous;
        } else if (!currentTarget && select.options.length > 1) {
            select.selectedIndex = 1;
            currentTarget = select.value || '';
        }
        // No borres el objetivo solo porque el raycast no lo vio durante un tick.
        // Esto evita que una reapertura o un frame de streaming deje las acciones sin objetivo.

        if (currentTarget) {
            const opt = select.options[select.selectedIndex];
            document.getElementById('status').innerText = `Objetivo seleccionado: ${opt.textContent}`;
        }
    }

    if (data.action === 'setDispatchUnits') {
        currentUnits=Math.max(1,Math.min(maxUnits,Number(data.units)||1));
        document.getElementById('units').value=currentUnits;
        document.getElementById('units-value').innerText=currentUnits;
    }

    if (data.action === 'policeMenuStatus') {
        document.getElementById('status').innerText=data.message || '';
    }

    if (data.action === 'showJailTimer') {
        const el=document.getElementById('jail-timer'); el.classList.remove('hidden');
        document.getElementById('jail-reason').innerText='Motivo: '+data.reason;
        let seconds=Number(data.minutes||1)*60;
        const timeEl=document.getElementById('jail-time');
        if (jailInterval) clearInterval(jailInterval);
        const tick=()=>{ const m=Math.floor(seconds/60).toString().padStart(2,'0'); const s=(seconds%60).toString().padStart(2,'0'); timeEl.innerText=`${m}:${s}`; };
        tick(); jailInterval=setInterval(()=>{seconds--;tick();if(seconds<=0){clearInterval(jailInterval);el.classList.add('hidden');}},1000);
    }
    if (data.action === 'setJailMinutes') {
        const el=document.getElementById('jail-timer'); if(!el.classList.contains('hidden')){
            if(jailInterval)clearInterval(jailInterval); let seconds=Math.max(60,Number(data.minutes||1)*60); const timeEl=document.getElementById('jail-time');
            const tick=()=>{const m=Math.floor(seconds/60).toString().padStart(2,'0');const s=(seconds%60).toString().padStart(2,'0');timeEl.innerText=`${m}:${s}`;};
            tick(); jailInterval=setInterval(()=>{seconds--;tick();if(seconds<=0){clearInterval(jailInterval);el.classList.add('hidden');}},1000);
        }
    }
    if (data.action === 'hideJailTimer') { document.getElementById('jail-timer').classList.add('hidden'); if(jailInterval)clearInterval(jailInterval); }
});

document.getElementById('close-menu').onclick=closeMenu;
document.getElementById('open-suspect').onclick=()=>{
    currentTarget=document.getElementById('target-select').value || currentTarget || '';
    if(!currentTarget){ document.getElementById('status').innerText='Apunta directamente a la persona que quieres detener y selecciónala.'; return; }
    document.getElementById('suspect-panel').classList.remove('hidden');
};
document.getElementById('close-suspect').onclick=()=>document.getElementById('suspect-panel').classList.add('hidden');
document.getElementById('units').addEventListener('input', e => {
    currentUnits=Math.max(1,Math.min(maxUnits,Number(e.target.value)||1));
    document.getElementById('units-value').innerText=currentUnits;
});
document.addEventListener('keydown', e => { if(e.key==='Escape') closeMenu(); });
