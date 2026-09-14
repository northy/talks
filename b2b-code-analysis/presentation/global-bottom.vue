<template>
  <footer
    v-if="$nav.currentLayout !== 'cover' && $nav.currentLayout !== 'end'"
    class="absolute bottom-0 left-0 right-0 text-right p-2"
  >
    {{ $nav.currentPage }}
  </footer>
</template>
