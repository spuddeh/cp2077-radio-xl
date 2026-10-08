import type { CSSProperties } from 'react'

/**
 * A station icon as the game draws it: the image multiplied by the widget's tint (currentColor),
 * cut to the image's own alpha. A white icon comes out the UI colour; a coloured one is darkened
 * toward it, as radioIcon's MainColors.PanelBlue tint does in game.
 */
export function tintedIcon(url: string): CSSProperties {
  return {
    backgroundColor: 'currentColor',
    backgroundImage: `url(${url})`,
    backgroundBlendMode: 'multiply',
    backgroundSize: 'contain',
    backgroundRepeat: 'no-repeat',
    backgroundPosition: 'center',
    maskImage: `url(${url})`,
    maskSize: 'contain',
    maskRepeat: 'no-repeat',
    maskPosition: 'center',
  }
}
