#!/usr/bin/env python3
"""Create static performance figures from saved results; requires matplotlib."""
import argparse, json, os, pathlib
os.environ.setdefault('MPLCONFIGDIR','/private/tmp/unit-test-design-matplotlib')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import NullFormatter

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('results',type=pathlib.Path,nargs='+')
    p.add_argument('--out',type=pathlib.Path,required=True)
    args=p.parse_args()
    studies=[json.loads(f.read_text()) for f in args.results]
    jobs={r['spec']['id']:r for study in studies for r in study['results']}
    colors={'ipog':'#146c94','gnd':'#cf6b21','gnd10':'#677b32'}
    fig,axs=plt.subplots(2,2,figsize=(12,8),layout='constrained')
    for ax,ladder,xlabel in ((axs[0,0],'arguments','Arguments (2 options each)'),(axs[0,1],'options','Options per argument (8 arguments)')):
        for solver in ('ipog','gnd'):
            selected=[r for r in jobs.values() if r['spec']['ladder']==ladder+'-'+solver and r['status']=='ok' and 'warm_median_seconds' in r]
            selected.sort(key=lambda r:r['spec']['n' if ladder=='arguments' else 'v'])
            x=[r['spec']['n' if ladder=='arguments' else 'v'] for r in selected]
            y=[r['warm_median_seconds'] for r in selected]
            ax.plot(x,y,'o-',label=solver.upper(),color=colors[solver])
            ax.errorbar(x,y,yerr=[[r['warm_median_seconds']-r['warm_min_seconds'] for r in selected],
                [r['warm_max_seconds']-r['warm_median_seconds'] for r in selected]],fmt='none',color=colors[solver],capsize=3)
        ax.set(xscale='log',yscale='log',xlabel=xlabel,ylabel='Warm call seconds');ax.legend();ax.grid(alpha=.2)
        dimension='n' if ladder=='arguments' else 'v'
        ticks=sorted({r['spec'][dimension] for r in jobs.values() if r['spec']['ladder'].startswith(ladder+'-') and r['status']=='ok' and 'warm_median_seconds' in r})
        ax.set_xticks(ticks,[str(tick) for tick in ticks]);ax.xaxis.set_minor_formatter(NullFormatter())
    labels=['arguments','noop_scoped','noop_whole','scoped','whole','matching','chain','equality','equality-cheap-explanations']
    ax=axs[1,0]
    xs=[];ys=[];names=[]
    for label in labels:
        r=next((r for r in jobs.values() if r['spec']['ladder']==label+'-ipog' and r['spec']['n']==32 and r['status']=='ok'),None)
        if r and 'warm_median_seconds' in r:
            names.append(label.replace('-cheap-explanations',' (budget 1)'));ys.append(r['warm_median_seconds']);xs.append(len(xs))
    ax.barh(xs,ys,color=colors['ipog']);ax.set_yticks(xs,names);ax.invert_yaxis();ax.set(xscale='log',xlabel='Warm IPOG seconds, 32 binary arguments');ax.grid(axis='x',alpha=.2)
    ax=axs[1,1];peaks=[];argument_ticks=set()
    for family,usage,label,color in [('none','reuse','Ordinary IPOG',colors['ipog']),
        ('none','seed','One partial seed','#677b32'),('noop_scoped','reuse','Scoped no-op','#8756a4'),
        ('none','report','Rich report',colors['gnd'])]:
        selected=sorted([r for r in jobs.values() if r['spec']['solver']=='ipog' and r['spec']['family']==family and r['spec']['usage']==usage and r['spec']['v']==2 and r['spec']['strength']==2 and r['status'] in ('ok','rss_limit')],key=lambda r:r['spec']['n'])
        complete=[r for r in selected if r['status']=='ok']
        rss=lambda r:(r.get('os_peak_rss_bytes') or r.get('sampled_peak_rss_bytes',0))/2**20
        peaks.extend(rss(r) for r in selected);argument_ticks.update(r['spec']['n'] for r in selected)
        ax.plot([r['spec']['n'] for r in complete],[rss(r) for r in complete],'o-',label=label,color=color)
        censored=[r for r in selected if r['status']=='rss_limit']
        ax.scatter([r['spec']['n'] for r in censored],[rss(r) for r in censored],marker='x',color=color,s=70)
    guards=sorted({float(study['metadata']['limits']['rss_mib']) for study in studies if study.get('metadata',{}).get('limits',{}).get('rss_mib')})
    for guard in guards: ax.axhline(guard,color='#777',linestyle='--',linewidth=1,label=f'{guard:g} MiB guard')
    handles,labels=ax.get_legend_handles_labels()
    handles.append(Line2D([],[],marker='x',color='#333',linestyle='None'));labels.append('RSS stop')
    ax.legend(handles,labels,loc='upper left',fontsize=9)
    ax.set(xscale='log',xlabel='Binary arguments',ylabel='Whole-process peak RSS MiB',ylim=(0,max(peaks+guards+[1])*1.1));ax.grid(alpha=.2)
    ticks=sorted(argument_ticks)
    ticks=sorted(set(ticks[::2]+ticks[-1:]))
    ax.set_xticks(ticks,[str(tick) for tick in ticks]);ax.xaxis.set_minor_formatter(NullFormatter())
    fig.suptitle('UnitTestDesign.jl — saved benchmark results\nWarm timings: completed jobs only; RSS includes compilation and diagnostics',fontsize=12)
    fig.savefig(args.out,dpi=160)
    fig.savefig(args.out.with_suffix('.svg'))
    svg=args.out.with_suffix('.svg')
    svg.write_text('\n'.join(line.rstrip() for line in svg.read_text().splitlines())+'\n')
if __name__=='__main__': main()
