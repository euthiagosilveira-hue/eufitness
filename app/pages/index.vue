<script setup lang="ts">
// Só decide para qual painel mandar quem já está logado.
const { load } = useMe()
const me = await load()
await navigateTo(homeFor(me), { replace: true })
</script>

<template>
  <div />
</template>
