/// Copyright (c) 2021 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit

class FlickrPhotosCollectionViewController: UICollectionViewController {
  private let reuseIdentifier = "FlickrCell"
  private let sectionInsets = UIEdgeInsets(top: 50, left: 20, bottom: 50, right: 20)
  private var searches: [FlickrSearchResults] = []
  private let flickr = Flickr()
  private let itemsPerRow: CGFloat = 3
  var largePhotoIndexPath: IndexPath? {
    didSet {
      var indexPaths = [IndexPath]()
      if let largePhotoIndexPath = largePhotoIndexPath {
        indexPaths.append(largePhotoIndexPath)
      }
      
      if let oldValue = oldValue {
        indexPaths.append(oldValue)
      }
      
      collectionView.performBatchUpdates {
        self.collectionView.reloadItems(at: indexPaths)
      } completion: { _ in
        if let largePhotoIndexPath = self.largePhotoIndexPath {
          self.collectionView.scrollToItem(at: largePhotoIndexPath, at: .centeredVertically, animated: true)
        }
      }
    }
  }
  
  var selectedPhotos = [FlickrPhoto]()
  let shareTextLabel = UILabel()
  var isSharing = false {
    didSet {
      collectionView.allowsMultipleSelection = isSharing
      
      collectionView.selectItem(at: nil, animated: true, scrollPosition: [])
      selectedPhotos.removeAll()
      
      guard let shareButton = navigationItem.rightBarButtonItems?.first else { return }
      
      guard isSharing else {
        navigationItem.setRightBarButtonItems([shareButton], animated: true)
        return
      }
      
      if largePhotoIndexPath != nil {
        largePhotoIndexPath = nil
      }
      
      updateSharedPhotoCountLabel()
      
      let sharingItem = UIBarButtonItem(customView: shareTextLabel)
      let items: [UIBarButtonItem] = [shareButton, sharingItem]
      
      navigationItem.setRightBarButtonItems(items, animated: true)
    }
  }
  
  override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
    guard !isSharing else { return true}
    
    if largePhotoIndexPath == indexPath {
      largePhotoIndexPath = nil
    } else {
      largePhotoIndexPath = indexPath
    }
    
    return false
  }
  
  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard isSharing else {
      return
    }
    
    let flickrPhoto = photo(for: indexPath)
    selectedPhotos.append(flickrPhoto)
    updateSharedPhotoCountLabel()
  }
  
  override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
    guard isSharing else {
      return
    }
    
    let flickrPhoto = photo(for: indexPath)
    if let index = selectedPhotos.firstIndex(of: flickrPhoto) {
      selectedPhotos.remove(at: index)
      updateSharedPhotoCountLabel()
    }
  }
  
  func performLargeImageFetch(for indexPath: IndexPath, flickrPhoto: FlickrPhoto, cell: FlickrPhotoCellCollectionViewCell) {
    cell.activityIndicator.startAnimating()
    
    flickrPhoto.loadLargeImage { [weak self] result in
      cell.activityIndicator.stopAnimating()
      
      guard let self = self else { return }
      
      switch result {
      case .success(let photo):
        if indexPath == self.largePhotoIndexPath {
          cell.imageView.image = photo.largeImage
        }
      case .failure:
        return
      }
    }
  }
  
  func updateSharedPhotoCountLabel() {
    if isSharing {
      shareTextLabel.text = "\(selectedPhotos.count) photos selected"
    } else {
      shareTextLabel.text = ""
    }
    
    shareTextLabel.textColor = themeColor
    
    UIView.animate(withDuration: 0.3) {
      self.shareTextLabel.sizeToFit()
    }
  }
    @IBAction func shareButtonTapped(_ sender: UIBarButtonItem) {
      guard !searches.isEmpty else { return }
      guard !selectedPhotos.isEmpty else {
        isSharing.toggle()
        return
      }
      guard isSharing else { return }
      
      let images: [UIImage] = selectedPhotos.compactMap { photo in
        guard let thumbnail = photo.thumbnail else {
          return nil
        }
        
        return thumbnail
      }
      
      guard !images.isEmpty else {
        return
      }
      
      let shareController = UIActivityViewController(activityItems: images, applicationActivities: nil)
      shareController.completionWithItemsHandler = { _, _, _, _ in
        self.isSharing = false
        self.selectedPhotos.removeAll()
        self.updateSharedPhotoCountLabel()
      }
      
      shareController.popoverPresentationController?.barButtonItem = sender
      shareController.popoverPresentationController?.permittedArrowDirections = .any
      present(shareController, animated: true)
    }
}

private extension FlickrPhotosCollectionViewController {
  func photo(for indexPath: IndexPath) -> FlickrPhoto {
    searches[indexPath.section].searchResults[indexPath.row]
  }
}

extension FlickrPhotosCollectionViewController: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    guard let text = textField.text, !text.isEmpty else { return true }
    
    let activityIndicator = UIActivityIndicatorView(style: .medium)
    activityIndicator.frame = textField.bounds
    textField.addSubview(activityIndicator)
    activityIndicator.startAnimating()
    
    flickr.searchFlickr(for: text) { searchResults in
      DispatchQueue.main.async {
        activityIndicator.removeFromSuperview()
        
        switch searchResults {
        case .failure(let error):
          print("Error searching: \(error)")
          
        case .success(let results):
          print("""
            Found \(results.searchResults.count) \
            matching \(results.searchTerm)
            """)
          self.searches.insert(results, at: 0)
          self.collectionView.reloadData()
        }
      }
    }
    
    textField.text = nil
    textField.resignFirstResponder()
    return true
  }
}

extension FlickrPhotosCollectionViewController {
  override func numberOfSections(in collectionView: UICollectionView) -> Int {
    searches.count
  }
  
  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    searches[section].searchResults.count
  }
  
  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: reuseIdentifier,
      for: indexPath
    ) as! FlickrPhotoCellCollectionViewCell
    
    let flickPhoto = photo(for: indexPath)
    
    cell.activityIndicator.stopAnimating()
    
    guard let largePhotoIndexPath = largePhotoIndexPath else {
      cell.imageView.image = flickPhoto.thumbnail
      return cell
    }
    
    cell.isSelected = true
    
    guard flickPhoto.largeImage == nil else {
      cell.imageView.image = flickPhoto.largeImage
      return cell
    }
    
    cell.imageView.image = flickPhoto.thumbnail
    
    performLargeImageFetch(for: largePhotoIndexPath, flickrPhoto: flickPhoto, cell: cell)
    
    return cell
  }
  
  override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
    switch kind {
    case UICollectionView.elementKindSectionHeader:
      let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "\(FlickrPhotoHeaderView.self)", for: indexPath)
      
      guard let typedHeaderView = headerView as? FlickrPhotoHeaderView else { return headerView }
      
      let searchTerm = searches[indexPath.section].searchTerm
      typedHeaderView.titleLabel.text = searchTerm
      return typedHeaderView
    default:
      assert(false, "Invalid supplementary element type")
    }
  }
}

extension FlickrPhotosCollectionViewController: UICollectionViewDelegateFlowLayout {
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    if largePhotoIndexPath == indexPath {
      let flickrPhoto = photo(for: indexPath)
      var size = collectionView.bounds.size
      size.height -= (sectionInsets.top + sectionInsets.bottom)
      size.width -= (sectionInsets.left + sectionInsets.right)
      return flickrPhoto.sizeToFillWidth(of: size)
    }
    
    let paddingSpace = sectionInsets.left * (itemsPerRow + 1)
    let availableWidth = view.frame.width - paddingSpace
    let widthPerItem = availableWidth / itemsPerRow
    
    return CGSize(width: widthPerItem, height: widthPerItem)
  }
  
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
    sectionInsets
  }
  
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
    sectionInsets.left
  }
}
