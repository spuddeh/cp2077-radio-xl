export interface VanillaStation {
  frequency: number
  name: string
  /** The station's own `UIIcon` record, as its `RadioStation` record names it. */
  icon: string
}

/** The fourteen, in dial order. The frequency is the front of each display name. */
export const VANILLA_STATIONS: VanillaStation[] = [
  { frequency: 88.9, name: 'Pacific Dreams', icon: 'UIIcon.RadioDowntempo' },
  { frequency: 89.3, name: 'Radio Vexelstrom', icon: 'UIIcon.RadioAggroIndie' },
  { frequency: 89.7, name: 'Growl FM', icon: 'UIIcon.RadioGrowlFM' },
  { frequency: 91.9, name: 'Royal Blue Radio', icon: 'UIIcon.RadioJazz' },
  { frequency: 92.9, name: 'Night FM', icon: 'UIIcon.RadioElectroIndie' },
  { frequency: 95.2, name: 'Samizdat Radio', icon: 'UIIcon.RadioMinimTech' },
  { frequency: 96.1, name: 'Ritual FM', icon: 'UIIcon.RadioMetal' },
  { frequency: 98.7, name: 'Body Heat Radio', icon: 'UIIcon.RadioPop' },
  { frequency: 99.9, name: 'Impulse', icon: 'UIIcon.RadioImpulse' },
  { frequency: 101.9, name: 'The Dirge', icon: 'UIIcon.RadioHipHop' },
  { frequency: 103.5, name: 'Radio PEBKAC', icon: 'UIIcon.RadioAggroTechno' },
  { frequency: 106.9, name: '30 Principales', icon: 'UIIcon.RadioLatino' },
  { frequency: 107.3, name: 'Morro Rock Radio', icon: 'UIIcon.RadioAttitudeRock' },
  { frequency: 107.5, name: 'Dark Star', icon: 'UIIcon.RadioDarkStar' },
]
