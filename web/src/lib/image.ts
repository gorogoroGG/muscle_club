function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.onerror = (event) => {
      URL.revokeObjectURL(url)
      reject(event)
    }
    img.src = url
  })
}

// Center-crops to a square and downsizes so uploads stay tiny (~10-30KB)
// and avatars load fast for everyone.
export async function resizeToSquareJpeg(file: File, size = 256): Promise<Blob> {
  const img = await loadImage(file)
  const canvas = document.createElement('canvas')
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('canvas unavailable')

  const scale = Math.max(size / img.naturalWidth, size / img.naturalHeight)
  const width = img.naturalWidth * scale
  const height = img.naturalHeight * scale
  ctx.drawImage(img, (size - width) / 2, (size - height) / 2, width, height)

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('toBlob failed'))), 'image/jpeg', 0.85)
  })
}
