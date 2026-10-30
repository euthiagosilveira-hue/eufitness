<script setup lang="ts">
const props = withDefaults(defineProps<{ name: string; size?: number; color?: string }>(), {
  size: 46,
  color: '#C6F432',
})

const initials = computed(() =>
  props.name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]!.toUpperCase())
    .join('') || '?',
)
</script>

<template>
  <div
    class="flex shrink-0 items-center justify-center rounded-full font-display font-bold text-ink"
    :style="{ width: `${size}px`, height: `${size}px`, background: color, fontSize: `${Math.round(size / 3)}px` }"
  >
    {{ initials }}
  </div>
</template>
