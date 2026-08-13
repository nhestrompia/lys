import {
  AppWindow,
  Boxes,
  FileCheck2,
  ShieldCheck,
  type LucideIcon,
} from 'lucide-react';

type TrailStep = {
  title: string;
  description: string;
  detail: string;
  icon: LucideIcon;
};

const steps: TrailStep[] = [
  {
    title: 'Install Lys',
    description: 'Build the public alpha and select an iOS project.',
    detail: 'Local toolchain',
    icon: AppWindow,
  },
  {
    title: 'Instrument the app',
    description: 'Bind stable semantics to real screens and controls.',
    detail: 'React Native or Swift',
    icon: Boxes,
  },
  {
    title: 'Export the contract',
    description: 'Validate reachable, bounded flows before an agent runs.',
    detail: '.lys/contract.json',
    icon: FileCheck2,
  },
  {
    title: 'Run with evidence',
    description: 'Let the host build, interact, and record fresh proof.',
    detail: 'Build · Launch · UI · Screenshot',
    icon: ShieldCheck,
  },
];

export function ProofTrail() {
  return (
    <section aria-labelledby="proof-trail-title" className="proof-trail">
      <div className="proof-trail-intro">
        <h2 id="proof-trail-title">Follow the proof trail</h2>
        <p>
          Lys keeps implementation and verification in one causal chain. Each stage produces the
          context needed by the next.
        </p>
      </div>

      <ol className="proof-trail-list">
        {steps.map((step, index) => {
          const Icon = step.icon;
          return (
            <li className="proof-trail-step" key={step.title}>
              <span className="proof-trail-marker" aria-hidden="true">
                {index + 1}
              </span>
              <div className="proof-trail-content">
                <div className="proof-trail-heading">
                  <span className="proof-trail-icon" aria-hidden="true">
                    <Icon size={19} strokeWidth={1.8} />
                  </span>
                  <div>
                    <h3>{step.title}</h3>
                    <span>{step.detail}</span>
                  </div>
                </div>
                <p>{step.description}</p>
              </div>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
