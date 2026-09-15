export interface VanillaStation {
  frequency: number
  name: string
  /** The station's own `UIIcon` record, as its `RadioStation` record names it. */
  icon: string
  /** Its part in radiostations_icons.inkatlas. */
  part: string
}

/** The fourteen, in dial order. The frequency is the front of each display name. */
export const VANILLA_STATIONS: VanillaStation[] = [
  { frequency: 88.9, name: 'Pacific Dreams', icon: 'UIIcon.RadioDowntempo', part: 'pacific_dreams' },
  { frequency: 89.3, name: 'Radio Vexelstrom', icon: 'UIIcon.RadioAggroIndie', part: 'vexElsTrom' },
  { frequency: 89.7, name: 'Growl FM', icon: 'UIIcon.RadioGrowlFM', part: 'growl_fm' },
  { frequency: 91.9, name: 'Royal Blue Radio', icon: 'UIIcon.RadioJazz', part: 'royal_blue' },
  { frequency: 92.9, name: 'Night FM', icon: 'UIIcon.RadioElectroIndie', part: 'night_fm' },
  { frequency: 95.2, name: 'Samizdat Radio', icon: 'UIIcon.RadioMinimTech', part: 'radio_samizdat' },
  { frequency: 96.1, name: 'Ritual FM', icon: 'UIIcon.RadioMetal', part: 'ritual' },
  { frequency: 98.7, name: 'Body Heat Radio', icon: 'UIIcon.RadioPop', part: 'body_heat' },
  { frequency: 99.9, name: 'Impulse', icon: 'UIIcon.RadioImpulse', part: 'impulse_999' },
  { frequency: 101.9, name: 'The Dirge', icon: 'UIIcon.RadioHipHop', part: 'the_dirge' },
  { frequency: 103.5, name: 'Radio PEBKAC', icon: 'UIIcon.RadioAggroTechno', part: 'radio_pebkac' },
  { frequency: 106.9, name: '30 Principales', icon: 'UIIcon.RadioLatino', part: '30_principales' },
  { frequency: 107.3, name: 'Morro Rock Radio', icon: 'UIIcon.RadioAttitudeRock', part: 'morro_rock' },
  { frequency: 107.5, name: 'Dark Star', icon: 'UIIcon.RadioDarkStar', part: 'dark_star' },
]

const LOGOS = import.meta.glob<string>('./assets/stations/*.png', { eager: true, import: 'default' })

/** The logo image for a vanilla station's icon record, or undefined for any other record. */
export function stationLogo(icon: string): string | undefined {
  const station = VANILLA_STATIONS.find((v) => v.icon === icon)
  return station && LOGOS[`./assets/stations/${station.part}.png`]
}
