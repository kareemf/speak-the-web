import SwiftUI

/// View containing playback controls for the text-to-speech
struct PlaybackControlsView: View {
    @ObservedObject var viewModel: ReaderViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)

                        // Progress track
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * viewModel.speechService.progress, height: 4)
                            .cornerRadius(2)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let percentage = value.location.x / geometry.size.width
                                let clampedPercentage = max(0, min(1, percentage))
                                if let article = viewModel.article {
                                    let position = Int(Double(article.content.count) * clampedPercentage)
                                    viewModel.speechService.seekTo(position: position)
                                }
                            }
                    )
                }
                .frame(height: 4)

                // Progress text
                HStack {
                    Text(viewModel.progressText)
                    Spacer()
                    Text(viewModel.estimatedTimeRemaining)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Main controls
            HStack(spacing: 32) {
                // Skip backward
                Button(action: { viewModel.speechService.skipBackward() }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                // Play/Pause
                Button(action: { viewModel.speechService.togglePlayPause() }) {
                    Image(systemName: viewModel.speechService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                // Skip forward
                Button(action: { viewModel.speechService.skipForward() }) {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                }
            }
            .foregroundColor(.accentColor)

            // Speed control
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(.secondary)

                Picker("Speed", selection: $viewModel.selectedRateIndex) {
                    ForEach(0..<SpeechService.ratePresets.count, id: \.self) { index in
                        Text(SpeechService.ratePresets[index].name)
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // Stop button
            Button(action: { viewModel.speechService.stop() }) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline)
            }
            .foregroundColor(.secondary)
            .padding(.bottom, 8)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }
}

#Preview {
    PlaybackControlsView(viewModel: ReaderViewModel())
}
